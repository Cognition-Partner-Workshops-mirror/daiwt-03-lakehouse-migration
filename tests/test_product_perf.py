import json
import re
from pathlib import Path

import yaml

from registry import load, validate

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/product_perf'
CONTRACT = json.loads((ROOT / 'src/parity/contract.json').read_text())
ETL = (UNIT / 'etl.sql').read_text()
REPORT = (UNIT / 'report.sql').read_text()


def test_registry_schema():
    registry = load(ROOT)
    spec = json.loads((UNIT / 'unit.json').read_text())
    assert registry['product_perf'] == spec
    assert set(spec) == {'job', 'legacy_unit', 'outputs', 'owns', 'depends_on'}
    assert spec['job'] == 'product_perf' and spec['legacy_unit'] == 'product_perf'
    contract_tables = {o['table'] for o in CONTRACT['outputs'] if o['unit'] == 'product_perf'}
    assert set(spec['outputs']) == contract_tables
    assert spec['owns'] == []
    assert all(dep in registry for dep in spec['depends_on'])
    validate(registry, CONTRACT)


def test_job_sql_file_tasks():
    resource = yaml.safe_load((UNIT / 'product_perf.job.yml').read_text())
    assert set(resource['resources']['jobs']) == {'product_perf'}
    job = resource['resources']['jobs']['product_perf']
    assert job['name'] == '${var.job_name_prefix}product_perf'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    assert job['tags']['environment'] == '${bundle.target}'
    tasks = job['tasks']
    assert [t['task_key'] for t in tasks] == ['build_product_perf', 'build_report']
    assert tasks[1]['depends_on'] == [{'task_key': 'build_product_perf'}]
    for task, filename in zip(tasks, ['etl.sql', 'report.sql']):
        sql = task['sql_task']
        assert sql['warehouse_id'] == '${var.warehouse_id}'
        assert sql['file'] == {'path': './' + filename, 'source': 'WORKSPACE'}
        assert sql['parameters']['catalog'] == '${var.catalog}'
        assert sql['parameters']['gold_schema'] == '${var.gold_schema}'
    assert 'permissions' not in job and 'run_as' not in job


def referenced(sql, schema):
    return set(re.findall(r":catalog \|\| '\.' \|\| :" + schema + r" \|\| '\.(\w+)'", sql))


def test_reads_and_writes():
    assert referenced(ETL, 'silver_schema') == {'order_items', 'orders', 'stores', 'products'}
    assert referenced(ETL, 'gold_schema') == {'product_perf'}
    assert referenced(REPORT, 'gold_schema') == {'product_perf', 'report_product_perf'}
    for sql in (ETL, REPORT):
        assert 'BEGIN' not in sql and 'DECLARE' not in sql
        assert 'daiwt_03' not in sql


def test_redshift_semantics():
    assert 'ORDER BY units DESC NULLS FIRST, region ASC NULLS LAST' in ETL
    assert 'rn <= 3' in ETL
    assert "rtrim(region)" in ETL
    assert 'AS DECIMAL(18,2)) AS revenue' in ETL
    assert 'LEFT JOIN agg' in ETL and 'LEFT JOIN top_stores' in ETL
    assert 'AS DECIMAL(38,2))' in REPORT
