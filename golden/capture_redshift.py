"""Operator-run, Data-API-only capture of the daiwt_03 source estate."""
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys
import time

import yaml

REGION = "us-east-1"
WORKGROUP = "daiwt-03-retail"
DATABASE = "daiwt_03_retail"
SECRET = "arn:aws:secretsmanager:us-east-1:599083837640:secret:daiwt-03-redshift-connection-A7dpBy"
NULL = "\\N"
OID_TYPES = {16: "bool", 20: "int8", 21: "int2", 23: "int4", 25: "text",
             700: "float4", 701: "float8", 1042: "bpchar", 1043: "varchar",
             1082: "date", 1114: "timestamp", 1184: "timestamptz",
             1700: "numeric", 4000: "super"}


def utcnow():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def identifier(name):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError(f"Invalid SQL identifier: {name}")
    return '"' + name + '"'


def table_sql(table):
    return ".".join(identifier(part) for part in table.split("."))


def render_cell(value, type_name):
    if value is None:
        return NULL
    kind = type_name.lower()
    if kind in ("numeric", "decimal") and isinstance(value, float):
        raise ValueError("NUMERIC must be returned as a Redshift string, not float")
    if kind in ("bool", "boolean"):
        if isinstance(value, str):
            if value.lower() not in ("true", "false", "t", "f"):
                raise ValueError(f"Invalid boolean: {value}")
            value = value.lower() in ("true", "t")
        return "true" if value else "false"
    if kind in ("float4", "float8", "real", "double precision"):
        return repr(float(value))
    if kind in ("timestamp", "timestamptz", "timestamp with time zone", "timestamp without time zone"):
        value = value if isinstance(value, dt.datetime) else dt.datetime.fromisoformat(value)
        if kind in ("timestamptz", "timestamp with time zone"):
            value = value.replace(tzinfo=dt.timezone.utc) if value.tzinfo is None else value.astimezone(dt.timezone.utc)
        return value.isoformat(sep=" ")
    if isinstance(value, bytes):
        return value.hex()
    return str(value)


def decode(field):
    if field.get("isNull"):
        return None
    return next(iter(field.values()))


class DataAPI:
    def __init__(self, client=None):
        if client is None:
            import boto3
            client = boto3.client("redshift-data", region_name=REGION)
        self.client, self.session_id = client, None
        self.query("SET timezone TO 'UTC'")
        self.timezone = self.query("SELECT current_setting('timezone')")[1][0][0]
        if self.timezone != "UTC":
            raise RuntimeError(f"Expected UTC, got {self.timezone}")

    def query(self, sql):
        options = {"Sql": sql, "SessionKeepAliveSeconds": 300}
        if self.session_id:
            options["SessionId"] = self.session_id
        else:
            options.update(WorkgroupName=WORKGROUP, Database=DATABASE, SecretArn=SECRET)
        result = self.client.execute_statement(**options)
        self.session_id = result.get("SessionId", self.session_id)
        if not self.session_id:
            raise RuntimeError("Data API did not return a persistent SessionId")
        statement = result["Id"]
        deadline = time.monotonic() + 900
        while True:
            status = self.client.describe_statement(Id=statement)
            if status["Status"] == "FINISHED":
                break
            if status["Status"] in ("FAILED", "ABORTED"):
                raise RuntimeError(status.get("Error", status["Status"]))
            if time.monotonic() > deadline:
                self.client.cancel_statement(Id=statement)
                raise TimeoutError("Data API statement timed out")
            time.sleep(0.5)
        columns, rows = [], []
        if status.get("HasResultSet"):
            options = {"Id": statement}
            while True:
                page = self.client.get_statement_result(**options)
                columns = page["ColumnMetadata"]
                rows.extend([[decode(cell) for cell in row] for row in page["Records"]])
                if not page.get("NextToken"):
                    break
                options["NextToken"] = page["NextToken"]
        return columns, rows


def profile(api):
    import boto3
    _, settings = api.query("SELECT version(), current_setting('timezone'), current_setting('search_path')")
    _, tables = api.query("SELECT table_schema, table_name FROM information_schema.tables "
                          "WHERE table_schema IN ('core','mart') AND table_type = 'BASE TABLE' "
                          "ORDER BY table_schema, table_name")
    inventory = [{"table": f"{schema}.{table}", "row_count": api.query(
        f"SELECT COUNT(*) FROM {table_sql(schema + '.' + table)}")[1][0][0]} for schema, table in tables]
    _, routines = api.query("SELECT n.nspname, p.proname FROM pg_proc p JOIN pg_namespace n "
                            "ON p.pronamespace = n.oid WHERE n.nspname = 'public' ORDER BY p.proname")
    required = {"f_fiscal_qtr", "f_clean_phone", "sp_build_churn_flags", "sp_upsert_inventory"}
    if not required.issubset({row[1] for row in routines}):
        raise RuntimeError(f"Missing routines: {required - {row[1] for row in routines}}")
    wg = boto3.client("redshift-serverless", region_name=REGION).get_workgroup(workgroupName=WORKGROUP)["workgroup"]
    return {"engine": "Amazon Redshift Serverless", "version": settings[0][0],
            "timezone": settings[0][1], "search_path": settings[0][2], "workgroup": wg["workgroupName"],
            "namespace": wg["namespaceName"], "region": REGION, "database": DATABASE,
            "schemas": ["core", "mart"], "tables": inventory, "routines": routines}


def inspect_csv(path, columns, keys, legacy_order=False):
    names = [column["name"] for column in columns]
    indices = [names.index(key) for key in keys]
    seen, previous, count = set(), None, 0
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.reader(stream)
        if next(reader) != names:
            raise ValueError(f"Header mismatch: {path}")
        for row in reader:
            if len(row) != len(names):
                raise ValueError(f"Row width mismatch: {path}")
            key = tuple(row[i] for i in indices)
            if key in seen:
                raise ValueError(f"Duplicate key in {path}: {key}")
            seen.add(key)
            order = tuple("" if value == NULL else value for value in key)
            if legacy_order and previous is not None and order <= previous:
                raise ValueError(f"Legacy ordering is not total in {path}: {key}")
            previous = order
            count += 1
    return count


def export_table(api, table, keys, path, page_size=10000):
    metadata, _ = api.query(f"SELECT * FROM {table_sql(table)} LIMIT 0")
    columns = [{"name": col["name"].lower(), "redshift_type": col["typeName"]} for col in metadata]
    names = [col["name"] for col in columns]
    if not keys or not set(keys).issubset(names):
        raise ValueError(f"Missing export keys for {table}")
    grouped = ", ".join(identifier(key) for key in keys)
    _, duplicates = api.query(f"SELECT 1 FROM {table_sql(table)} GROUP BY {grouped} HAVING COUNT(*) > 1 LIMIT 1")
    if duplicates:
        keys = names
    expressions = []
    for col in columns:
        name, kind = identifier(col["name"]), col["redshift_type"].lower()
        expression = f"JSON_SERIALIZE({name})" if kind == "super" else f"TO_HEX({name})" if kind == "varbyte" else name
        expressions.append(expression + " AS " + name)
    order = ", ".join(identifier(key) for key in keys)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(names)
        offset = 0
        while True:
            _, rows = api.query(f"SELECT {', '.join(expressions)} FROM {table_sql(table)} "
                                f"ORDER BY {order} LIMIT {page_size} OFFSET {offset}")
            writer.writerows([[render_cell(value, col["redshift_type"]) for value, col in zip(row, columns)] for row in rows])
            if len(rows) < page_size:
                break
            offset += len(rows)
    count = inspect_csv(path, columns, keys)
    return {"sha256": sha256(path), "row_count": count, "columns": columns, "keys": keys,
            "source_table": table, "reused_from_legacy_run": False, "matches_committed_golden": None}


def ordered_outputs(units):
    for wave in units["waves"]:
        for name in wave["units"]:
            for output in units["units"][name]["outputs"]:
                yield name, output


def skipped_branches(units):
    return [{"unit": name, "path": path, "reason": "capture_skip; " + (
        "UNLOAD destination and IAM role are placeholders; not run by cmdBuild" if path.endswith("export.sql") else
        "scheduler specification, not installed; load_core uses unsupported --ddl-only; finance_export step not run by cmdBuild")}
        for name, unit in units["units"].items() for path in unit.get("capture_skip", [])]


def build_manifest(source, files, units, captured_at):
    files = [dict(entry) for entry in files]
    entries = {entry["path"]: entry for entry in files}
    tables = []
    for unit, output in ordered_outputs(units):
        if "table" in output:
            path = f"outputs/D0/{unit}/{output['name']}.csv"
            entries[path]["table"] = output["table"]
            tables.append({"table": output["table"], "path": path,
                           "columns": [col["name"] for col in entries[path]["columns"]]})
    return {"source": source, "capture_mode": "legacy_run", "captured_at_utc": captured_at,
            "session_timezone": "UTC", "drops": ["D0"],
            "drops_reason": "seed generator anchored to 2025-12-31; setup drops and reloads core from committed seed CSVs; full-reload ETL, no incremental loads",
            "batch_semantics": "D0 full reload from the legacy commit's fixed seed; no incremental drops",
            "csv_conventions": {"self_exported": {"encoding": "UTF-8", "header": "lowercase", "line_endings": "LF", "quoting": "RFC4180", "null": NULL,
                "numeric": "Redshift string, never float", "float": "Python shortest round-trip repr", "boolean": "true/false", "timestamp": "YYYY-MM-DD HH:MM:SS[.ffffff]", "timestamptz": "UTC +00:00", "date": "YYYY-MM-DD", "char": "padding preserved", "super": "JSON_SERIALIZE", "varbyte": "hex", "ordering": "SQL ORDER BY full unique key, LIMIT/OFFSET plus Data API NextToken paging"},
                "reused_legacy": {"encoding": "UTF-8", "header": "lowercase", "line_endings": "LF", "quoting": "RFC4180", "null": NULL, "rendering": "legacy renderCell: fixed-point Decimal, repr(float), true/false, datetime.isoformat, other str; UTC sessions; CHAR unchanged"}},
            "nondeterministic_columns": [], "skipped_branches": skipped_branches(units),
            "format_exceptions": ["Reused legacy capture uses SELECT * then Python sort on rendered key strings with NULL->empty string; verified unique keys and strict total order. Files copied byte-for-byte."],
            "files": files, "tables": tables}


def legacy_launcher(legacy, run):
    for var in ("REDSHIFT_HOST", "REDSHIFT_PORT", "REDSHIFT_USER", "REDSHIFT_PASSWORD"):
        os.environ.pop(var, None)
    os.environ.update(REDSHIFT_ADMIN_DATABASE=DATABASE, AWS_REGION=REGION,
                      REDSHIFT_SECRET="daiwt-03-redshift-connection", REDSHIFT_DATA_API="1")
    sys.path.insert(0, str(legacy))
    import tools.redshift_data_api as api
    original = api.Cursor.execute
    sessions = []

    def execute(cursor, sql, parameters=None):
        connection = cursor.connection
        if connection.options["Database"] != DATABASE or connection.options["WorkgroupName"] != WORKGROUP:
            raise RuntimeError("Legacy connection is outside the authorized estate")
        if connection.session_id is None:
            original(cursor, "SET timezone TO 'UTC'")
            timezone = original(cursor, "SELECT current_setting('timezone')").fetchone()[0]
            if timezone != "UTC":
                raise RuntimeError(f"Expected UTC, got {timezone}")
            sessions.append({"session_id": connection.session_id, "timezone": timezone})
        return original(cursor, sql, parameters)

    api.Cursor.execute = execute
    os.chdir(legacy)
    sys.argv = [str(legacy / "tools/source_connection.py"), "all"]
    try:
        runpy.run_path(sys.argv[0], run_name="__main__")
    finally:
        write_json(run / "sessions.json", sessions)


def prepare_legacy(root, repo, commit, skip):
    legacy, run = root / "legacy", root / "run"
    run.mkdir(parents=True, exist_ok=True)
    if not skip:
        if legacy.exists():
            raise FileExistsError(f"Refusing to reset existing capture: {legacy}")
        subprocess.run(["git", "clone", repo, str(legacy)], check=True)
        subprocess.run(["git", "checkout", "--detach", commit], cwd=legacy, check=True)
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=legacy, text=True).strip()
    if actual != commit:
        raise ValueError(f"Legacy commit mismatch: {actual}")
    if not skip:
        (run / "legacy_start.txt").write_text(utcnow() + "\n")
        with (run / "legacy_run.log").open("w") as log:
            result = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--_legacy-launch", str(legacy), str(run)], stdout=log, stderr=subprocess.STDOUT)
            log.write(f"\nEXIT {result.returncode}\n")
        (run / "legacy_end.txt").write_text(utcnow() + "\n")
        if result.returncode:
            raise RuntimeError(f"Legacy run failed: EXIT {result.returncode}")
    log = (run / "legacy_run.log").read_text()
    note = None
    if not re.search(r"^EXIT 0$", log, re.MULTILINE):
        capture_phase = re.search(r"^\S+ == capture$", log, re.MULTILINE)
        completed = capture_phase and re.search(r"^\S+ done$", log[capture_phase.end():], re.MULTILINE)
        if not skip or not completed:
            raise RuntimeError("No successful EXIT 0 or completed legacy capture in legacy_run.log")
        note = ("Legacy runner completed (setup, build, capture, 'done'); the original ad-hoc launcher exited 1 afterwards "
                "while writing sessions.json (relative path after chdir); sessions.json reconstructed from the launcher's per-session timezone log lines.")
    sessions = json.loads((run / "sessions.json").read_text())
    if not sessions or any(session["timezone"] != "UTC" for session in sessions):
        raise RuntimeError("Missing UTC legacy session evidence")
    return legacy, sessions, note


def capture(root, legacy, source, units, api, captured_at):
    files = []
    for output in units["units"]["foundation"]["outputs"]:
        relative = f"inputs/D0/core.{output['name']}.csv"
        entry = export_table(api, "core." + output["name"], output["keys"], root / relative)
        files.append(dict(entry, path=relative))
    for unit, output in ordered_outputs(units):
        origin = legacy / output["golden"]
        meta = json.loads(origin.with_suffix(".meta.json").read_text())
        columns = [{"name": col["name"], "redshift_type": OID_TYPES[col["redshift_type_oid"]]} for col in meta["columns"]]
        count = inspect_csv(origin, columns, output["keys"], legacy_order=True)
        if count != meta["row_count"] or sha256(origin) != meta["sha256"]:
            raise ValueError(f"Legacy metadata mismatch: {origin}")
        relative = f"outputs/D0/{unit}/{output['name']}.csv"
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origin, destination)
        committed = subprocess.check_output(["git", "show", f"{source['legacy_commit']}:{output['golden']}"], cwd=legacy)
        entry = {"path": relative, "sha256": sha256(destination), "row_count": count, "columns": columns,
                 "keys": output["keys"], "reused_from_legacy_run": True,
                 "matches_committed_golden": hashlib.sha256(committed).hexdigest() == sha256(destination)}
        if "table" in output:
            entry["source_table"] = output["table"].replace("silver.", "core.").replace("gold.", "mart.")
        files.append(entry)
    return build_manifest(source, files, units, captured_at)


def verify(root, manifest, api):
    results = []
    for entry in manifest["files"]:
        path = root / entry["path"]
        if sha256(path) != entry["sha256"] or inspect_csv(path, entry["columns"], entry["keys"], entry["reused_from_legacy_run"]) != entry["row_count"]:
            raise ValueError(f"File verification failed: {path}")
        if entry.get("source_table"):
            live = api.query(f"SELECT COUNT(*) FROM {table_sql(entry['source_table'])}")[1][0][0]
            if live != entry["row_count"]:
                raise ValueError(f"Live row count mismatch: {path}")
        if not entry["reused_from_legacy_run"]:
            again = export_table(api, entry["source_table"], entry["keys"], root / "run/reexport" / entry["path"])
            if again["sha256"] != entry["sha256"]:
                raise ValueError(f"Input export is not deterministic: {path}")
        print(f"D0 {entry['path']}: {entry['row_count']} rows", flush=True)
        results.append({"path": entry["path"], "sha256": entry["sha256"], "row_count": entry["row_count"], "verified": True})
    output = next(entry for entry in manifest["files"] if entry.get("source_table", "").startswith("mart.") and entry["row_count"] > 1)
    first = export_table(api, output["source_table"], output["keys"], root / "run/output_spotcheck_1.csv")
    second = export_table(api, output["source_table"], output["keys"], root / "run/output_spotcheck_2.csv")
    if first["sha256"] != second["sha256"]:
        raise ValueError("Output export is not deterministic")
    write_json(root / "run/verify.json", {"verified_at_utc": utcnow(), "session_timezone": api.timezone,
        "files": results, "output_spotcheck": {"table": output["source_table"], "sha256": first["sha256"]},
        "scope": "Export determinism spot-check, not a second ETL run"})


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--_legacy-launch":
        legacy_launcher(Path(sys.argv[2]), Path(sys.argv[3]))
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-dir", required=True, type=Path)
    parser.add_argument("--legacy-repo", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--skip-legacy-run", action="store_true")
    parser.add_argument("--captured-at", default=utcnow())
    args = parser.parse_args()
    captured_at = dt.datetime.fromisoformat(args.captured_at.replace("Z", "+00:00"))
    if captured_at.utcoffset() != dt.timedelta(0):
        parser.error("--captured-at must be UTC")
    root = args.capture_dir.expanduser().resolve()
    if (root / "manifest.json").exists():
        raise FileExistsError("Refusing to overwrite existing capture manifest")
    root.mkdir(parents=True, exist_ok=True)
    legacy, sessions, note = prepare_legacy(root, args.legacy_repo, args.commit, args.skip_legacy_run)
    units = yaml.safe_load((legacy / ".migration/units.yaml").read_text())
    source = profile(DataAPI())
    source.update(legacy_repo=args.legacy_repo, legacy_commit=args.commit,
                  legacy_command="make legacy-all == python tools/source_connection.py all",
                  legacy_sessions=sessions, legacy_start=(root / "run/legacy_start.txt").read_text().strip(),
                  legacy_end=(root / "run/legacy_end.txt").read_text().strip())
    if note:
        source["legacy_run_note"] = note
    write_json(root / "run/profile.json", source)
    api = DataAPI()
    manifest = capture(root, legacy, source, units, api, args.captured_at)
    verify(root, manifest, DataAPI())
    write_json(root / "manifest.json", manifest)
    print(f"manifest.json sha256 {sha256(root / 'manifest.json')}")


if __name__ == "__main__":
    main()
