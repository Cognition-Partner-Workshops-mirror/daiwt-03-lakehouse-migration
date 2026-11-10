import importlib.util
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/governance'
spec = importlib.util.spec_from_file_location('governance', UNIT / 'governance.py')
governance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(governance)


def fixture():
    registry = {'producer': {'legacy_unit': 'old', 'outputs': ['silver.items', 'gold.report_old'],
                             'owns': ['bronze.stage', 'gold.absent']}}
    contract = {'outputs': [dict(table=table, kind=kind, path=path,
                                columns=[{'name': 'id`x', 'redshift_type': "var'char\\type"}])
                            for table, kind, path in [('silver.items', 'table', "outputs/D0/a'b.csv"),
                                                      ('silver.items', 'table', 'outputs/D1/items.csv'),
                                                      ('gold.report_old', 'report', 'outputs/D0/report.csv')]]}
    schemas = {'bronze': 'b', 'silver': 's', 'gold': 'g'}
    existing = {('s', 'items'): {'table_type': 'MANAGED'},
                ('g', 'report_old'): {'table_type': 'VIEW'},
                ('b', 'stage'): {'table_type': 'EXTERNAL'}}
    return registry, contract, 'cat`alog', schemas, "o`wner", existing


def test_registry_contract_plan_and_escaping():
    plans = governance.build_plan(*fixture())
    table, report, owned, missing = plans
    assert missing['status'] == 'SKIP' and missing['statements'] == []
    assert 'Redshift core.items' in table['comment']
    assert "outputs/D0/a'b.csv" in table['comment'] and 'outputs/D1/items.csv' in table['comment']
    assert 'report query of legacy unit old' in report['comment']
    assert owned['tags']['contract_kind'] == 'owned' and owned['tags']['parity'] == 'none'
    assert owned['columns'] == {}
    assert table['tags'] == dict(source_system='redshift', medallion_layer='silver',
                                migration_unit='producer', legacy_unit='old', contract_kind='table',
                                owner_unit='producer', parity='golden')
    sql = '\n'.join(statement for _, statement in table['statements'])
    assert '`cat``alog`.`s`.`items`' in sql and '`id``x`' in sql and '`o``wner`' in sql
    assert "a\\'b.csv" in sql and "var\\'char\\\\type" in sql
    assert "a''b" not in sql
    assert report['statements'][0][1].startswith('COMMENT ON VIEW')
    assert governance.literal("a\nb\rc\x00") == "'a\\nb\\rc\\0'"


@pytest.mark.parametrize('kind,form', [('MANAGED', 'TABLE'), ('EXTERNAL', 'TABLE'),
    ('VIEW', 'VIEW'), ('MATERIALIZED_VIEW', 'MATERIALIZED VIEW'), ('STREAMING_TABLE', 'STREAMING TABLE')])
def test_statement_forms(kind, form):
    args = fixture()
    args[-1][('s', 'items')]['table_type'] = kind
    plan = governance.build_plan(*args)[0]
    sql = dict(plan['statements'])
    assert sql['comment'].startswith(f"COMMENT ON {'VIEW' if form == 'VIEW' else 'TABLE'} ")
    assert sql['tags'].startswith(f'ALTER {form} ')
    assert sql['owner'].startswith(f'ALTER {form} ')


def test_empty_and_invalid_contract():
    args = fixture()
    assert governance.build_plan({}, *args[1:]) == []
    args[1]['outputs'] = []
    with pytest.raises(ValueError, match='No contract'):
        governance.build_plan(*args)


def test_check_metadata_and_pipeline_exemptions():
    plan = governance.build_plan(*fixture())[0]
    key = (plan['schema'], plan['name'])
    tables = {key: {'comment': plan['comment'], 'table_owner': plan['owner']}}
    tags, columns = {key: plan['tags'].copy()}, {key: plan['columns'].copy()}
    assert governance.mismatches(plan, tables, tags, columns) == []
    tables[key]['comment'] = None
    tables[key]['table_owner'] = 'wrong'
    tags[key].pop('parity')
    columns[key] = {}
    assert set(governance.mismatches(plan, tables, tags, columns)) == {'comment', 'owner', 'tag:parity', 'column:id`x'}
    assert governance.mismatches(plan, tables, tags, columns, ['comment', 'owner', 'column:id`x']) == ['tag:parity']


def test_job_serverless_and_separate_check():
    job = yaml.safe_load((UNIT / 'governance.job.yml').read_text())['resources']['jobs']['governance']
    assert job['name'] == '${var.job_name_prefix}governance'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    assert [task['task_key'] for task in job['tasks']] == ['apply_governance', 'check_governance']
    assert job['tasks'][1]['depends_on'] == [{'task_key': 'apply_governance'}]
    for task in job['tasks']:
        assert not any('cluster' in key for key in task)
        assert task['notebook_task']['base_parameters']['bundle_root'] == '${workspace.file_path}'
        assert task['notebook_task']['base_parameters']['data_owner'] == '${var.data_owner}'


def test_information_schema_reads_use_correct_schema_fields():
    class Spark:
        def __init__(self):
            self.queries = []

        def sql(self, query):
            self.queries.append(query)
            return self

        def collect(self):
            return []

    spark = Spark()
    assert governance.read_state(spark, 'catalog', {'bronze': 'b'}) == ({}, {}, {})
    assert 'table_schema IN' in spark.queries[0]
    assert 'schema_name IN' in spark.queries[1]
    assert 'table_schema IN' in spark.queries[2]
