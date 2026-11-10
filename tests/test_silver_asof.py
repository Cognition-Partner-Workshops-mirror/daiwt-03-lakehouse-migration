import json
import re
from pathlib import Path

import pytest
import yaml

from classify_changes import expand
from registry import load, validate

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/silver_asof'
SQL = (UNIT / 'functions.sql').read_text()
CHECK = (UNIT / 'self_check.sql').read_text()
BRONZE = (ROOT / 'src/sql/units/bronze_landing/load.sql').read_text()
TABLES = dict(re.findall(
    r"CREATE TABLE IF NOT EXISTS IDENTIFIER\(:catalog \|\| '\.' \|\| :bronze_schema \|\| '\.(\w+)'\) \((.*?)\) USING DELTA;",
    BRONZE, re.S))


def business_columns(declaration):
    fields = re.split(r',\s*(?![^()]*\))', declaration.strip())
    return [field.replace(' NOT NULL', '') for field in fields
            if not field.startswith(('_drop ', '_loaded_at '))]


def drop_seq(value):
    if value is None or not re.fullmatch(r'D[0-9]+', value):
        return None
    seq = int(value[1:])
    return seq if seq <= 2147483647 else None


def resolve(loaded, target):
    target_seq = drop_seq(target)
    if target_seq is None:
        return None
    eligible = [(drop_seq(label), loaded_at, label) for label, loaded_at in loaded
                if drop_seq(label) is not None and drop_seq(label) <= target_seq]
    return max(eligible)[2] if eligible else None


@pytest.mark.parametrize('value,expected', [
    ('D0', 0), ('D12', 12), ('D01', 1), ('D2147483647', 2147483647),
    ('D2147483648', None), (None, None), ('', None), ('D', None), ('d1', None),
    ('D-1', None), ('D1.0', None), (' D1', None), ('D1 ', None), ('D1x', None),
    ('D١', None), ('D1\n', None),
])
def test_drop_seq_semantics(value, expected):
    assert drop_seq(value) == expected
    assert r"d RLIKE r'^D[0-9]+\z'" in SQL
    assert 'try_cast(substring(d, 2) AS INT) ELSE NULL END' in SQL
    assert 'RETURNS INT\nDETERMINISTIC' in SQL


@pytest.mark.parametrize('loaded,target,expected', [
    ([('D0', 1), ('D1', 2)], 'D0', 'D0'),
    ([('D0', 1), ('D1', 2)], 'D1', 'D1'),
    ([('D0', 1), ('D1', 2)], 'D5', 'D1'),
    ([('D2', 100), ('D10', 1)], 'D12', 'D10'),
    ([('D2', 100)], 'D0', None), ([], 'D0', None),
    ([('D0', 1), ('invalid', 2)], 'D5', 'D0'),
    ([('D0', 1)], 'invalid', None), ([('D0', 1)], None, None),
    ([('D1', 1), ('D01', 2)], 'D5', 'D01'),
    ([('D1', 1), ('D01', 1)], 'D5', 'D1'),
])
def test_latest_numeric_snapshot_resolution(loaded, target, expected):
    assert resolve(loaded, target) == expected


def test_global_drop_preserves_empty_table_in_newer_snapshot():
    tables = {'customers': [('D0', 1), ('D1', 2)], 'stores': [('D0', 1)]}
    effective = resolve([row for rows in tables.values() for row in rows], 'D5')
    assert effective == 'D1'
    assert [row for row in tables['stores'] if row[0] == effective] == []
    assert resolve(tables['stores'], 'D5') == 'D0'


def test_unit_registry_and_dependency_expansion():
    registry = load(ROOT)
    assert registry['silver_asof'] == {
        'job': 'silver_asof', 'legacy_unit': 'foundation',
        'outputs': [], 'owns': [], 'depends_on': ['bronze_landing']}
    validate(registry, json.loads((ROOT / 'src/parity/contract.json').read_text()))
    assert expand(registry, ['silver_asof']) == ['bronze_landing', 'silver_asof']


@pytest.mark.parametrize('table', TABLES)
def test_function_business_schema_and_fully_qualified_snapshot_body(table):
    columns = business_columns(TABLES[table])
    body = re.search(r"\.\`asof_" + table + r"\`\(as_of_drop STRING\)(.*?)FROM ' \|\| bronze \|\| '\.\`" + table + r"\`\n       WHERE _drop = ' \|\| silver \|\| '\.\`resolve_drop\`\(as_of_drop\)'", SQL, re.S).group(1)
    assert 'RETURNS TABLE (' + ', '.join(columns) + ')' in body
    assert 'SELECT ' + ', '.join(column.split()[0] for column in columns) in body


def test_one_global_resolver_includes_every_bronze_table():
    resolver = SQL.split('EXECUTE IMMEDIATE')[1]
    assert '.`resolve_drop`(as_of_drop STRING)' in resolver
    assert "WHERE seq <= ' || silver || '.`drop_seq`(as_of_drop)" in resolver
    assert "'.`drop_seq`(_drop) AS seq, max(_loaded_at) AS loaded_at" in resolver
    assert 'ORDER BY seq DESC, loaded_at DESC, _drop DESC' in resolver
    assert 'GROUP BY _drop' in resolver and 'LIMIT 1' in resolver
    assert resolver.count('UNION ALL') == len(TABLES) - 1
    for table in TABLES:
        assert "SELECT _drop, _loaded_at FROM ' || bronze || '.`" + table + '`' in resolver


def test_dynamic_ddl_is_escaped_and_only_creates_functions():
    assert SQL.count('EXECUTE IMMEDIATE') == len(TABLES) + 1
    for param in ('catalog', 'silver_schema', 'bronze_schema'):
        assert "replace(:" + param + ", '`', '``')" in SQL
    assert not re.search(r'\b(?:CREATE TABLE|DELETE|INSERT|UPDATE|MERGE|DROP TABLE)\b', SQL, re.I)
    assert not re.search(r'\bSELECT\s+\*', SQL, re.I)


def test_self_check_counts_types_column_order_and_scalar_cases():
    assert 'bool_and(IDENTIFIER' in CHECK
    assert "('D2147483648', NULL)" in CHECK and '(NULL, NULL)' in CHECK
    assert 'actual_rows = expected_rows' in CHECK
    assert 'bronze_columns.business_columns = function_columns.business_columns' in CHECK
    assert "column_name NOT IN ('_drop', '_loaded_at')" in CHECK
    assert '.information_schema.routine_columns' in CHECK
    assert CHECK.count('sort_array(collect_list(struct(') == 2
    assert CHECK.count('lower(') == 2
    assert "ELSE raise_error(concat('silver_asof mismatch: '" in CHECK
    for table in TABLES:
        assert f"'.asof_{table}')(:drop)" in CHECK
        assert f"SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.{table}')" in CHECK
    assert CHECK.count('WHERE _drop = (SELECT resolved_drop FROM effective)') == len(TABLES)


@pytest.mark.parametrize('metadata,expected', [
    ('string', 'string'), ('string collate UTF8_BINARY', 'string'),
    ('decimal(12,2)', 'decimal(12,2)'),
    ('string collate UTF8_LCASE', 'string collate utf8_lcase'),
])
def test_schema_comparison_normalizes_only_default_string_collation(metadata, expected):
    assert re.sub(r' collate utf8_binary$', '', metadata.lower()) == expected
    assert CHECK.count("' collate utf8_binary$', ''") == 2


def test_job_shape_and_parameters():
    jobs = yaml.safe_load((UNIT / 'silver_asof.job.yml').read_text())['resources']['jobs']
    assert set(jobs) == {'silver_asof'}
    job = jobs['silver_asof']
    assert job['name'] == '${var.job_name_prefix}silver_asof'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    assert job['tags'] == {'environment': '${bundle.target}'}
    assert 'run_as' not in job and 'permissions' not in job
    assert [task['task_key'] for task in job['tasks']] == ['create_functions', 'check_functions']
    assert job['tasks'][1]['depends_on'] == [{'task_key': 'create_functions'}]
    for task, filename in zip(job['tasks'], ['functions.sql', 'self_check.sql']):
        assert set(task) <= {'task_key', 'sql_task', 'depends_on'}
        sql = task['sql_task']
        assert sql['file'] == {'path': './' + filename, 'source': 'WORKSPACE'}
        assert sql['warehouse_id'] == '${var.warehouse_id}'
        assert sql['parameters'] == {
            **{key: '${var.' + key + '}' for key in ['catalog', 'bronze_schema', 'silver_schema', 'gold_schema']},
            'drop': '{{job.parameters.drop}}'}
