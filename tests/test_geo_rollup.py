import json
import re
from pathlib import Path

import yaml

from registry import load

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/geo_rollup'
ETL = (UNIT / 'etl.sql').read_text()
REPORT = (UNIT / 'report.sql').read_text()
CONTRACT = json.loads((ROOT / 'src/parity/contract.json').read_text())


def test_registry_entry_matches_contract_outputs():
    spec = load(ROOT)['geo_rollup']
    assert spec['job'] == 'geo_rollup'
    assert spec['legacy_unit'] == 'geo_rollup'
    contract = sorted(o['table'] for o in CONTRACT['outputs'] if o['unit'] == spec['legacy_unit'])
    assert sorted(spec['outputs']) == contract
    assert spec['owns'] == []
    assert spec['depends_on'] == sorted(spec['depends_on'])


def test_job_sql_file_tasks():
    resource = yaml.safe_load((UNIT / 'geo_rollup.job.yml').read_text())
    job = resource['resources']['jobs']['geo_rollup']
    assert job['name'] == '${var.job_name_prefix}geo_rollup'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    tasks = job['tasks']
    assert [t['task_key'] for t in tasks] == ['build_geo_rollup', 'publish_report']
    assert tasks[1]['depends_on'] == [{'task_key': 'build_geo_rollup'}]
    for task, filename in zip(tasks, ['etl.sql', 'report.sql']):
        sql = task['sql_task']
        assert sql['warehouse_id'] == '${var.warehouse_id}'
        assert sql['file'] == {'path': './' + filename, 'source': 'WORKSPACE'}
        assert sql['parameters']['catalog'] == '${var.catalog}'
        assert sql['parameters']['silver_schema'] == '${var.silver_schema}'
        assert sql['parameters']['gold_schema'] == '${var.gold_schema}'
    assert 'permissions' not in job and 'run_as' not in job


def test_sql_is_parameterized_and_has_no_scripting_blocks():
    for sql in (ETL, REPORT):
        assert not re.search(r'\b(BEGIN|DECLARE)\b', sql)
        assert 'daiwt_03' not in sql and '_pr_' not in sql
    for table in ('stores', 'orders', 'order_items'):
        assert f":silver_schema || '.{table}')" in ETL


def test_explicit_grouping_ids_and_sets():
    assert 'GROUPING SETS ((s.region), (s.state), ())' in ETL
    assert 'GROUPING(s.region) = 0 AND GROUPING(s.state) = 1 THEN 1' in ETL
    assert 'GROUPING(s.region) = 1 AND GROUPING(s.state) = 0 THEN 2' in ETL
    assert 'rpad(rtrim(region), 4, ' in ETL
    assert 'COUNT(DISTINCT o.order_id)' in ETL
    assert 'COALESCE(SUM(oi.quantity * (oi.unit_price - oi.discount)), 0)' in ETL
    assert 'LEFT JOIN' in ETL and 'INNER JOIN' not in ETL


def test_report_columns_match_contract():
    columns = next(o['columns'] for o in CONTRACT['outputs'] if o['table'] == 'gold.report_geo_rollup')
    select = ', '.join(c['name'] for c in columns)
    assert f'SELECT {select}' in REPORT
    assert '`report_geo_rollup`' in REPORT and '`geo_rollup`' in REPORT
