import io
import json
from types import SimpleNamespace

import pytest
from databricks.sdk.errors import NotFound, PermissionDenied

from drops import load_drops
from parity.parity_check import manifest_drops, output_entries, run
from check_attestation import evaluate
from attest import render


def client(manifest=None, error=None):
    def download(_):
        if error:
            raise error
        return SimpleNamespace(contents=io.BytesIO(json.dumps(manifest).encode()))
    return SimpleNamespace(files=SimpleNamespace(download=download),
                           volumes=SimpleNamespace(read=lambda _: None))


@pytest.mark.parametrize("drops", [["D0"], [{"name": "snapshot"}], ["first", {"name": "second"}]])
def test_manifest_drops(drops):
    assert manifest_drops({"drops": drops}) == [d["name"] if isinstance(d, dict) else d for d in drops]


@pytest.mark.parametrize("drops", [[], {}, ["D0", "D0"], ["../x"], [{}], [None]])
def test_invalid_drops(drops):
    with pytest.raises(ValueError):
        manifest_drops({"drops": drops})


def test_remote_missing_manifest():
    remote = client(error=NotFound("missing"))
    assert load_drops(remote) == ["D0"]
    result = run(remote, "daiwt_03_mig_dev", "pr_1", "w", {}, "D0")
    assert result["status"] == "PASS" and result["goldens"] == 0
    assert render(result)[1]


def test_remote_denied():
    with pytest.raises(PermissionDenied):
        load_drops(client(error=PermissionDenied("denied")))


def test_capture_outputs_are_skipped():
    manifest = {"drops": [{"name": "D0"}, "next"], "files": [
        {"path": "inputs/core.orders.csv", "columns": ["id"]},
        {"path": "outputs/D0/mart.sales.csv", "columns": [{"name": "id", "redshift_type": "bigint"}],
         "sha256": "hash", "row_count": 1, "keys": ["id"]},
        {"path": "outputs/next/mart.sales.csv", "columns": ["id"]},
    ]}
    entries = output_entries(manifest, "D0")
    assert len(entries) == 1 and entries[0]["columns"] == ["id"]
    assert entries[0]["table"] == "mart.sales"
    result = run(client(manifest), "daiwt_03_mig_dev", "pr_1", "w", {}, "D0")
    assert result["status"] == "PASS" and result["goldens"] == 1
    assert result["results"][0]["reason"] == "not yet migrated"
    assert render(result)[1]


def test_flat_and_legacy_entries():
    entry = {"table": "gold.sales", "path": "outputs/sales.csv", "columns": ["id"]}
    assert output_entries({"tables": [entry]}, "D0") == [entry]
    with pytest.raises(ValueError, match="unknown drop"):
        output_entries({"tables": []}, "absent")
    with pytest.raises(ValueError):
        output_entries({"files": [{**entry, "path": "outputs/../sales.csv"}]}, "D0")
    with pytest.raises(KeyError):
        output_entries({}, "D0")


def test_empty_attestation_and_current_drop_set():
    row = {"head_sha": "head", "suffix": "pr_1", "status": "PASS", "units": "[]",
           "drops": '{"D0": {"status": "PASS"}}', "attestation_md": "# PASS"}
    assert evaluate([row], "head", "pr_1", [], ["D0"])[0]
    assert not evaluate([row], "head", "pr_1", [], ["D0", "next"])[0]
    assert not evaluate([row], "head", "pr_1", ["new_unit"], ["D0"])[0]


def test_workflow_no_cancellation():
    from pathlib import Path
    import yaml
    for path in Path(".github/workflows").glob("*.yml"):
        assert yaml.safe_load(path.read_text())["concurrency"]["cancel-in-progress"] is False
