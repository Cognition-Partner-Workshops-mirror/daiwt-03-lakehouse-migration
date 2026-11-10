import csv
import importlib.util
import json
from pathlib import Path

import pytest

from parity.parity_check import compare, output_entries

SPEC = importlib.util.spec_from_file_location(
    "capture_redshift", Path(__file__).resolve().parents[1] / "golden/capture_redshift.py")
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


@pytest.mark.parametrize("value,kind,expected", [
    (None, "varchar", "\\N"), ("", "varchar", ""),
    ("1234567890123456789.1200", "numeric", "1234567890123456789.1200"),
    ("1.25", "float8", "1.25"), (False, "bool", "false"),
    ("f", "bool", "false"), (True, "boolean", "true"),
    ("AB  ", "bpchar", "AB  "), (b"\x00\xff", "varbyte", "00ff"),
    ("2025-12-31 12:00:00.000001", "timestamp", "2025-12-31 12:00:00.000001"),
    ("2025-12-31 12:00:00-05:00", "timestamptz", "2025-12-31 17:00:00+00:00"),
    ("2025-12-31", "date", "2025-12-31"),
])
def test_render(value, kind, expected):
    assert capture.render_cell(value, kind) == expected


def test_bad_boolean_and_identifier():
    with pytest.raises(ValueError, match="Invalid boolean"):
        capture.render_cell("invalid", "bool")
    with pytest.raises(ValueError, match="Invalid SQL identifier"):
        capture.identifier('a"; DROP TABLE core.orders')


class ExportAPI:
    def __init__(self, rows=(), duplicate=False):
        self.rows, self.duplicate, self.queries = list(rows), duplicate, []

    def query(self, sql):
        self.queries.append(sql)
        if "LIMIT 0" in sql:
            return [{"name": "id", "typeName": "int4"},
                    {"name": "value", "typeName": "numeric"}], []
        if "HAVING COUNT(*)" in sql:
            return [], [[1]] if self.duplicate else []
        offset = int(sql.split(" OFFSET ")[1])
        limit = int(sql.split(" LIMIT ")[1].split()[0])
        return [], self.rows[offset:offset + limit]


def test_export_csv_and_ordered_paging(tmp_path):
    api = ExportAPI([[1, "123456789012345.1200"], [2, None], [10, ""]])
    path = tmp_path / "inputs/D0/core.test.csv"
    result = capture.export_table(api, "core.test", ["id"], path, page_size=2)
    assert path.read_bytes() == b'id,value\n1,123456789012345.1200\n2,\\N\n10,\n'
    assert result["row_count"] == 3
    assert result["columns"][1]["redshift_type"] == "numeric"
    assert [sql.rsplit("OFFSET ", 1)[1] for sql in api.queries if "OFFSET" in sql] == ["0", "2"]
    assert all('ORDER BY "id"' in sql for sql in api.queries if "OFFSET" in sql)
    assert result["sha256"] == capture.sha256(path)


def test_empty_export_and_duplicate_key_fallback(tmp_path):
    empty = capture.export_table(ExportAPI(), "core.test", ["id"], tmp_path / "empty.csv")
    assert empty["row_count"] == 0
    api = ExportAPI([[1, "a"], [1, "b"]], duplicate=True)
    result = capture.export_table(api, "core.test", ["id"], tmp_path / "fallback.csv")
    assert result["keys"] == ["id", "value"]
    assert 'ORDER BY "id", "value"' in api.queries[-1]
    with pytest.raises(ValueError, match="Duplicate key"):
        capture.export_table(ExportAPI([[1, "a"], [1, "a"]], duplicate=True),
                             "core.test", ["id"], tmp_path / "duplicate.csv")


def test_rfc4180_and_legacy_total_order(tmp_path):
    path = tmp_path / "test.csv"
    columns = [{"name": "id"}, {"name": "value"}]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerows([["id", "value"], ["10", 'comma,quote"\nline'], ["2", "é"]])
    assert capture.inspect_csv(path, columns, ["id"], legacy_order=True) == 2
    path.write_text("id,value\n2,a\n10,b\n")
    with pytest.raises(ValueError, match="ordering is not total"):
        capture.inspect_csv(path, columns, ["id"], legacy_order=True)
    path.write_text("id,value\n\\N,a\n,b\n")
    with pytest.raises(ValueError, match="ordering is not total"):
        capture.inspect_csv(path, columns, ["id"], legacy_order=True)
    path.write_text("wrong,header\n")
    with pytest.raises(ValueError, match="Header mismatch"):
        capture.inspect_csv(path, columns, ["id"])


def test_manifest_parity_contract():
    units = {"waves": [{"units": ["test"]}], "units": {"test": {
        "outputs": [{"name": "table", "table": "gold.test"}, {"name": "report"}],
        "capture_skip": ["legacy/redshift/units/finance_export/export.sql"]}}}
    files = [{"path": f"outputs/D0/test/{name}.csv", "columns": [{"name": "id", "redshift_type": "int4"}]}
             for name in ("table", "report")]
    manifest = capture.build_manifest({"engine": "Redshift"}, files, units, "2026-11-10T14:24:33Z")
    manifest = json.loads(json.dumps(manifest))
    assert manifest["tables"] == [{"table": "gold.test", "path": "outputs/D0/test/table.csv", "columns": ["id"]}]
    result = compare(manifest, {}, None, None)
    assert result["status"] == "PASS"
    assert [row["status"] for row in result["results"]] == ["SKIP"]
    assert manifest["drops"] == ["D0"]
    assert "2025-12-31" in manifest["drops_reason"]
    assert manifest["skipped_branches"][0]["path"].endswith("export.sql")
    empty = capture.build_manifest({}, [], {"waves": [], "units": {}}, "2026-11-10T14:24:33Z")
    assert compare(empty, {}, None, None)["goldens"] == 0


def test_manifest_file_entries_have_explicit_target_tables():
    units = {"waves": [{"units": ["foundation", "daily_revenue"]}], "units": {
        "foundation": {"outputs": [{"name": "customers", "table": "silver.customers"}]},
        "daily_revenue": {"outputs": [{"name": "daily_revenue", "table": "gold.daily_revenue"},
                                      {"name": "report"}]}}}
    files = [{"path": path, "columns": [{"name": "id", "redshift_type": "int4"}]}
             for path in ("inputs/D0/core.customers.csv", "outputs/D0/foundation/customers.csv",
                          "outputs/D0/daily_revenue/daily_revenue.csv", "outputs/D0/daily_revenue/report.csv")]
    manifest = capture.build_manifest({}, files, units, "2026-11-10T14:24:33Z")
    outputs = output_entries(manifest, "D0")
    assert [entry["table"] for entry in outputs[:2]] == ["silver.customers", "gold.daily_revenue"]
    assert {entry["path"]: entry["table"] for entry in manifest["files"] if "table" in entry} == {
        entry["path"]: entry["table"] for entry in manifest["tables"]}
    assert "table" not in manifest["files"][0]
    assert "table" not in manifest["files"][-1]
    assert all("table" not in entry for entry in files)


class Client:
    def __init__(self, fail=False):
        self.calls, self.results, self.fail = [], {}, fail

    def execute_statement(self, **options):
        self.calls.append(options)
        number = str(len(self.calls))
        self.results[number] = options["Sql"]
        return {"Id": number, "SessionId": "session"}

    def describe_statement(self, Id):
        if self.fail:
            return {"Status": "FAILED", "Error": "permission denied"}
        return {"Status": "FINISHED", "HasResultSet": self.results[Id] != "SET timezone TO 'UTC'"}

    def get_statement_result(self, Id, NextToken=None):
        if "current_setting" in self.results[Id]:
            return {"ColumnMetadata": [{"name": "timezone", "typeName": "varchar"}], "Records": [[{"stringValue": "UTC"}]]}
        return {"ColumnMetadata": [{"name": "value", "typeName": "numeric"}],
                "Records": [[{"stringValue": "123.4500"}]] if not NextToken else [[{"isNull": True}]],
                **({"NextToken": "next"} if not NextToken else {})}


def test_api_utc_session_and_next_token():
    client = Client()
    api = capture.DataAPI(client)
    columns, rows = api.query("SELECT value FROM core.test")
    assert client.calls[0]["Sql"] == "SET timezone TO 'UTC'"
    assert client.calls[0]["Database"] == "daiwt_03_retail"
    assert all(call["SessionId"] == "session" for call in client.calls[1:])
    assert all(call["SessionKeepAliveSeconds"] == 300 for call in client.calls)
    assert rows == [["123.4500"], [None]]
    assert columns[0]["typeName"] == "numeric"


def test_api_failure_stops():
    with pytest.raises(RuntimeError, match="permission denied"):
        capture.DataAPI(Client(fail=True))


@pytest.mark.parametrize("log,accepted,note_expected", [
    ("EXIT 0\n", True, False),
    ("2026-11-10T14:00:00Z == setup\n2026-11-10T14:01:00Z == build\n"
     "2026-11-10T14:02:00Z == capture\n2026-11-10T14:03:00Z done\n"
     "Traceback\nFileNotFoundError: run/sessions.json\nEXIT 1\n", True, True),
    ("2026-11-10T14:02:00Z == capture\nEXIT 1\n", False, False),
    ("2026-11-10T14:01:00Z done\n2026-11-10T14:02:00Z == capture\nEXIT 1\n", False, False),
    ("2026-11-10T14:02:00Z == capture\nnot a completion done\nEXIT 1\n", False, False),
])
def test_prepare_completed_run(tmp_path, monkeypatch, log, accepted, note_expected):
    run = tmp_path / "run"
    run.mkdir()
    (run / "legacy_run.log").write_text(log)
    capture.write_json(run / "sessions.json", [{"session_id": "one", "timezone": "UTC"}])
    monkeypatch.setattr(capture.subprocess, "check_output", lambda *args, **kwargs: "abc\n")
    if not accepted:
        with pytest.raises(RuntimeError, match="No successful EXIT 0 or completed legacy capture"):
            capture.prepare_legacy(tmp_path, "repo", "abc", True)
        return
    legacy, sessions, note = capture.prepare_legacy(tmp_path, "repo", "abc", True)
    assert legacy == tmp_path / "legacy"
    assert sessions[0]["timezone"] == "UTC"
    assert bool(note) is note_expected
    if note_expected:
        assert note == ("Legacy runner completed (setup, build, capture, 'done'); the original ad-hoc launcher exited 1 afterwards "
                        "while writing sessions.json (relative path after chdir); sessions.json reconstructed from the launcher's per-session timezone log lines.")


def test_capture_copies_legacy_bytes_and_records_mismatch(tmp_path, monkeypatch):
    legacy = tmp_path / "legacy"
    origin = legacy / "golden/foundation/test.csv"
    origin.parent.mkdir(parents=True)
    origin.write_bytes(b"id,value\n1,1.00\n2,2.00\n")
    capture.write_json(origin.with_suffix(".meta.json"), {
        "columns": [{"name": "id", "redshift_type_oid": 23},
                    {"name": "value", "redshift_type_oid": 1700}],
        "row_count": 2, "sha256": capture.sha256(origin)})
    units = {"waves": [{"units": ["foundation"]}], "units": {"foundation": {
        "outputs": [{"name": "test", "table": "silver.test", "keys": ["id"],
                     "golden": "golden/foundation/test.csv"}]}}}
    monkeypatch.setattr(capture.subprocess, "check_output", lambda *args, **kwargs: b"old committed golden")
    manifest = capture.capture(tmp_path, legacy, {"legacy_commit": "abc"}, units,
                               ExportAPI([[1, "1.00"], [2, "2.00"]]), "2026-11-10T14:24:33Z")
    assert (tmp_path / "outputs/D0/foundation/test.csv").read_bytes() == origin.read_bytes()
    entry = manifest["files"][1]
    assert entry["reused_from_legacy_run"] is True
    assert entry["matches_committed_golden"] is False
    assert entry["source_table"] == "core.test"
    assert entry["columns"][1]["redshift_type"] == "numeric"


def test_verify_reexports_and_writes_evidence(tmp_path):
    class VerifyAPI(ExportAPI):
        timezone = "UTC"

        def query(self, sql):
            if sql.startswith("SELECT COUNT(*)"):
                return [], [[2]]
            return super().query(sql)

    api = VerifyAPI([[1, "1.00"], [2, "2.00"]])
    files = []
    for table, relative in [("core.test", "inputs/D0/core.test.csv"), ("mart.test", "outputs/D0/test/test.csv")]:
        entry = capture.export_table(api, table, ["id"], tmp_path / relative)
        entry.update(path=relative, reused_from_legacy_run=table.startswith("mart."))
        files.append(entry)
    capture.verify(tmp_path, {"files": files}, api)
    evidence = json.loads((tmp_path / "run/verify.json").read_text())
    assert len(evidence["files"]) == 2
    assert evidence["output_spotcheck"]["table"] == "mart.test"
    (tmp_path / files[0]["path"]).write_text("corrupted\n")
    with pytest.raises(ValueError, match="File verification failed"):
        capture.verify(tmp_path, {"files": files}, api)
