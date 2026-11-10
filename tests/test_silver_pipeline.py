import importlib.util
from pathlib import Path

import pytest
import yaml

from registry import load, with_dependencies
from classify_changes import classify
from parity.parity_check import GoldenStore, Warehouse, run
from test_contract import CONTRACT, MANIFEST
from test_manifest import client

ROOT = Path(__file__).resolve().parents[1]


def generated():
    spec = importlib.util.spec_from_file_location("silver_resources", ROOT / "silver_resources.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.load_resources(None).pipelines["silver"].as_dict()


def test_discovery_and_empty_scaffold():
    pipeline = generated()
    files = [entry["file"]["path"] for entry in pipeline["libraries"]]
    expected = sorted(str(path.relative_to(ROOT)) for path in
                      (ROOT / "src/sql/units").glob("silver_*/*.pipeline.sql")
                      if path.parent.name != "silver_pipeline")
    assert files == ["src/sql/units/silver_pipeline/placeholder.sql"] + expected
    assert pipeline["serverless"] is True
    assert pipeline["configuration"]["silver_bad_rows"] == "${var.silver_bad_rows}"
    assert "PRIVATE MATERIALIZED VIEW" in (ROOT / files[0]).read_text()


def test_discovery_adds_entity_without_shared_edits(tmp_path):
    spec = importlib.util.spec_from_file_location("silver_resources", ROOT / "silver_resources.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.__file__ = str(tmp_path / "silver_resources.py")
    for name in ("silver_example", "silver_pipeline", "other"):
        directory = tmp_path / "src/sql/units" / name
        directory.mkdir(parents=True)
        (directory / "example.pipeline.sql").write_text("SELECT 1")
    files = module.load_resources(None).pipelines["silver"].as_dict()["libraries"]
    assert [entry["file"]["path"] for entry in files] == [
        "src/sql/units/silver_pipeline/placeholder.sql",
        "src/sql/units/silver_example/example.pipeline.sql"]


def test_serverless_script_root_without_file(monkeypatch):
    import sys
    path = ROOT / "src/parity/parity_check.py"
    monkeypatch.setattr(sys, "argv", [str(path)])
    namespace = {"__name__": "serverless_test"}
    exec(compile(path.read_text(), str(path), "exec"), namespace)
    assert namespace["ROOT"] == ROOT


def test_generic_entity_contracts():
    registry = load(ROOT)
    for path in (ROOT / "src/sql/units").glob("silver_*/*.pipeline.sql"):
        if path.parent.name == "silver_pipeline":
            continue
        unit = path.parent.name
        entity = unit.removeprefix("silver_")
        spec = registry[unit]
        assert "silver." + entity + "_quarantine" in spec["owns"]
        assert "silver_pipeline" in spec["depends_on"]
        assert "'${silver_bad_rows}' = 'true'" in path.read_text()
        order = with_dependencies(registry, [unit])
        assert order.index("bronze_landing") < order.index("silver_asof")
        assert order.index("silver_asof") < order.index("silver_pipeline") < order.index(unit)


def test_transitive_builder_selection():
    registry = load(ROOT)
    registry["silver_example"] = dict(job="silver_example", legacy_unit="foundation",
        outputs=[], owns=[], depends_on=["silver_pipeline"])
    assert classify(registry, ["src/sql/units/silver_example/example.pipeline.sql"])["units"] == [
        "bronze_landing", "silver_asof", "silver_pipeline", "silver_example"]


def test_prod_flag_and_job_contract():
    config = yaml.safe_load((ROOT / "databricks.yml").read_text())
    assert config["variables"]["silver_bad_rows"]["default"] == "false"
    assert config["targets"]["prod"]["variables"]["silver_bad_rows"] == "false"
    job = yaml.safe_load((ROOT / "src/sql/units/silver_pipeline/silver_pipeline.job.yml").read_text())["resources"]["jobs"]["silver_pipeline"]
    refresh, verify = job["tasks"]
    assert refresh["pipeline_task"]["parameters"]["drop"] == "{{job.parameters.drop}}"
    assert verify["depends_on"] == [{"task_key": "refresh_silver"}]
    assert verify["spark_python_task"]["parameters"][6:8] == ["--layer", "silver"]


@pytest.mark.parametrize("registered,broken,status,compared", [
    (False, False, "PASS", 0), (True, False, "PASS", 1), (True, True, "FAIL", 1)])
def test_silver_only_parity(monkeypatch, registered, broken, status, compared):
    output = next(entry["table"] for entry in CONTRACT["outputs"] if entry["table"].startswith("silver."))
    registry = {"entity": dict(job="entity", legacy_unit="foundation", outputs=[output],
                               owns=[], depends_on=[])} if registered else {}
    monkeypatch.setattr(GoldenStore, "rows", lambda *_: [["same"]])
    def actual(_, query):
        assert "`silver_pr_1`" in query
        if broken:
            raise RuntimeError("read failed")
        return [["same"]]
    monkeypatch.setattr(Warehouse, "sql", actual)
    result = run(client(MANIFEST), "daiwt_03_mig_dev", "pr_1", "w", registry, layer="silver")
    assert result["status"] == status
    assert result["compared"] == compared
    assert all(row["table"].startswith("silver.") for row in result["results"])


def test_invalid_layer():
    with pytest.raises(ValueError, match="Unsupported parity layer"):
        run(None, "daiwt_03_mig_dev", "pr_1", "w", {}, layer="bronze")
