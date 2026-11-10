import json
import re
from pathlib import Path

import yaml

from registry import load, validate

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/inventory_snapshot'
CONTRACT = json.loads((ROOT / 'src/parity/contract.json').read_text())
ETL = (UNIT / 'etl.sql').read_text()
REPORT = (UNIT / 'report.sql').read_text()


def test_registry_schema():
    registry = load(ROOT)
    spec = json.loads((UNIT / 'unit.json').read_text())
    assert registry['inventory_snapshot'] == spec
    assert set(spec) == {'job', 'legacy_unit', 'outputs', 'owns', 'depends_on'}
    assert spec['job'] == 'inventory_snapshot' and spec['legacy_unit'] == 'inventory_snapshot'
    contract_tables = {o['table'] for o in CONTRACT['outputs'] if o['unit'] == 'inventory_snapshot'}
    assert set(spec['outputs']) == contract_tables
    assert spec['owns'] == []
    assert all(dep in registry for dep in spec['depends_on'])
    validate(registry, CONTRACT)


def test_job_sql_file_tasks():
    resource = yaml.safe_load((UNIT / 'inventory_snapshot.job.yml').read_text())
    assert set(resource['resources']['jobs']) == {'inventory_snapshot'}
    job = resource['resources']['jobs']['inventory_snapshot']
    assert job['name'] == '${var.job_name_prefix}inventory_snapshot'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    tasks = job['tasks']
    assert [t['task_key'] for t in tasks] == ['build_inventory_snapshot', 'build_report']
    assert tasks[1]['depends_on'] == [{'task_key': 'build_inventory_snapshot'}]
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
    assert referenced(ETL, 'silver_schema') == {'order_items', 'products'}
    assert referenced(ETL, 'gold_schema') == {'inventory_snapshot'}
    assert referenced(REPORT, 'gold_schema') == {'inventory_snapshot', 'report_inventory_snapshot'}
    for sql in (ETL, REPORT):
        assert 'BEGIN' not in sql and 'DECLARE' not in sql
        assert 'daiwt_03' not in sql


def test_redshift_semantics():
    assert "DATE'2025-12-31'" in ETL
    assert 'GREATEST(500 - COALESCE(s.units_sold, 0), 0) AS INT)' in ETL
    assert 'LEFT JOIN stg_inventory' in ETL
    assert 'ORDER  BY on_hand ASC NULLS LAST, product_id ASC NULLS LAST' in REPORT
    assert 'LIMIT  50' in REPORT
