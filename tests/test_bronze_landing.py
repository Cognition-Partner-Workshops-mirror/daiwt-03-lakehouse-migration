import csv
import io
import json
import re
from pathlib import Path

import pytest
import yaml

from registry import load, validate

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/bronze_landing'
LOAD = (UNIT / 'load.sql').read_text()
CHECK = (UNIT / 'self_check.sql').read_text()
MANIFEST = json.loads((ROOT / 'golden/manifest.json').read_text())

# Column/type snapshot of legacy/redshift/00_foundation/02_core_tables.sql.
SOURCE_DDL = {
    'customers': 'customer_id BIGINT NOT NULL, email VARCHAR(320), first_name VARCHAR(64), last_name VARCHAR(64), phone VARCHAR(32), region CHAR(4), preferred_store_id INT, signup_date DATE, is_business BOOLEAN',
    'stores': 'store_id INT NOT NULL, region CHAR(4), store_name VARCHAR(64), city VARCHAR(64), state VARCHAR(2)',
    'products': 'product_id INT NOT NULL, sku VARCHAR(16), product_name VARCHAR(128), category VARCHAR(32), subcategory VARCHAR(32), unit_price NUMERIC(12,2), cost NUMERIC(12,2), active BOOLEAN',
    'orders': 'order_id BIGINT NOT NULL, customer_id BIGINT, store_id INT, order_ts TIMESTAMP, sales_channel VARCHAR(16), status VARCHAR(16)',
    'order_items': 'order_item_id BIGINT NOT NULL, order_id BIGINT, product_id INT, quantity INT, unit_price NUMERIC(12,2), discount NUMERIC(12,2)',
    'payments': 'payment_id BIGINT NOT NULL, order_id BIGINT, method VARCHAR(16), amount NUMERIC(12,2), paid_ts TIMESTAMP',
    'returns': 'return_id BIGINT NOT NULL, order_item_id BIGINT, quantity INT, reason VARCHAR(64), returned_ts TIMESTAMP',
    'shipments': 'shipment_id BIGINT NOT NULL, order_id BIGINT, carrier VARCHAR(16), ship_ts TIMESTAMP, delivered_ts TIMESTAMP',
    'web_events': 'event_id BIGINT NOT NULL, customer_id BIGINT, event_ts TIMESTAMP, event_type VARCHAR(16), page_url VARCHAR(256)',
    'campaign_touches': 'touch_id BIGINT NOT NULL, customer_id BIGINT, payload SUPER',
}


def columns(ddl):
    return [tuple(field.split(' ', 1)) for field in re.split(r',\s*(?![^()]*\))', ddl.strip())]


def target_type(source):
    source = re.sub(r'(?:VAR)?CHAR\(\d+\)|SUPER', 'STRING', source)
    source = source.replace('NUMERIC', 'DECIMAL').replace('TIMESTAMP', 'TIMESTAMP_NTZ')
    return source


def declarations():
    return dict(re.findall(
        r"CREATE TABLE IF NOT EXISTS IDENTIFIER\(:catalog \|\| '\.' \|\| :bronze_schema \|\| '\.(\w+)'\) \((.*?)\) USING DELTA;",
        LOAD, re.S))


def test_unit_registry_and_manifest_table_list():
    spec = load(ROOT)['bronze_landing']
    assert spec['job'] == 'bronze_landing'
    assert spec['legacy_unit'] == 'foundation'
    assert spec['outputs'] == spec['depends_on'] == []
    assert set(spec['owns']) == {'bronze.' + table for table in SOURCE_DDL}
    assert set(declarations()) == set(SOURCE_DDL)
    validate({'bronze_landing': spec}, json.loads((ROOT / 'src/parity/contract.json').read_text()))
    inputs = [entry for entry in MANIFEST['files'] if entry['path'].startswith('inputs/')]
    assert {Path(entry['path']).stem.removeprefix('core.') for entry in inputs} == set(SOURCE_DDL)
    for entry in inputs:
        table = Path(entry['path']).stem.removeprefix('core.')
        assert [column['name'] for column in entry['columns']] == [name for name, _ in columns(SOURCE_DDL[table])]


@pytest.mark.parametrize('table', SOURCE_DDL)
def test_exact_legacy_types_column_order_and_strict_csv_casts(table):
    source = columns(SOURCE_DDL[table])
    expected = [(name, target_type(kind)) for name, kind in source]
    assert columns(declarations()[table]) == expected + [('_drop', 'STRING'), ('_loaded_at', 'TIMESTAMP')]
    reader_schema = ', '.join(name + ' STRING' for name, _ in source)
    assert "schema => '" + reader_schema + "'" in LOAD
    for name, kind in expected:
        assert f"CAST(NULLIF(COALESCE({name}, ''), r'\\N') AS {kind.replace(' NOT NULL', '')}) AS {name}" in LOAD
    target = f"IDENTIFIER(:catalog || '.' || :bronze_schema || '.{table}')"
    assert f'DELETE FROM {target} WHERE _drop = :drop;' in LOAD
    assert f"INSERT INTO {target} ({', '.join(name for name, _ in source)}, _drop, _loaded_at)" in LOAD
    assert f"'/core.{table}.csv'" in LOAD


def test_csv_options_and_lineage_are_explicit():
    for option in ["nullValue => '', emptyValue => ''", "quote => '\"', escape => '\"', multiLine => true",
                   'ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false',
                   "mode => 'FAILFAST', enforceSchema => false",
                   "rescuedDataColumn => '_rescued_data', readerCaseSensitive => true",
                   'WHERE CASE WHEN _rescued_data IS NULL THEN true']:
        assert LOAD.count(option) == 10
    assert LOAD.count(':drop, current_timestamp()') == 10
    assert 'TRY_CAST' not in LOAD.upper()
    assert not re.search(r'\b(TRUNCATE|OVERWRITE|DROP TABLE)\b', LOAD, re.I)
    assert "ELSE raise_error('Invalid drop name')" in LOAD


def normalize_cell(value):
    value = '' if value is None else value
    return None if value == r'\N' else value


@pytest.mark.parametrize('raw,expected', [(None, ''), ('', ''), (r'\N', None),
    (' padded ', ' padded '), ('MiXeD', 'MiXeD'), ('{"a":1}', '{"a":1}')])
def test_null_marker_is_distinct_from_csv_empty(raw, expected):
    assert normalize_cell(raw) == expected


def test_rfc4180_quoting_empty_and_newlines():
    rows = list(csv.reader(io.StringIO('id,a,b,c,d\n1,\\N,"",,"a,""b""\nc"\n')))
    assert [normalize_cell(cell) for cell in rows[1]] == ['1', None, '', '', 'a,"b"\nc']


def test_self_check_reads_live_manifest_and_checks_ordered_columns_and_counts():
    assert "read_files(:golden_path || '/manifest.json', format => 'json', multiLine => true" in CHECK
    assert 'LATERAL explode(files)' in CHECK
    assert 'transform(entry.columns, column -> column.name)' in CHECK
    assert 'max(row_count) AS expected_rows' in CHECK
    assert 'entries = 1 AND (SELECT count(*) FROM manifest) = 10' in CHECK
    assert 'actual_rows = expected_rows' in CHECK
    assert "actual_columns = concat(expected_columns, array('_drop', '_loaded_at'))" in CHECK
    assert 'sort_array(collect_list(struct(ordinal_position, column_name)))' in CHECK
    assert "ELSE raise_error(concat('bronze_landing mismatch: '" in CHECK
    for table in SOURCE_DDL:
        assert f"SELECT '{table}' AS table_name, count(*) AS actual_rows" in CHECK
        assert f"'.{table}') WHERE _drop = :drop" in CHECK
    assert CHECK.count('LEFT JOIN') == 2


def test_job_warehouse_tasks_and_parameters():
    jobs = yaml.safe_load((UNIT / 'bronze_landing.job.yml').read_text())['resources']['jobs']
    assert set(jobs) == {'bronze_landing'}
    job = jobs['bronze_landing']
    assert job['name'] == '${var.job_name_prefix}bronze_landing'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    assert job['tags']['environment'] == '${bundle.target}'
    assert 'run_as' not in job and 'permissions' not in job
    assert [task['task_key'] for task in job['tasks']] == ['load_inputs', 'check_inputs']
    assert job['tasks'][1]['depends_on'] == [{'task_key': 'load_inputs'}]
    for task, filename in zip(job['tasks'], ['load.sql', 'self_check.sql']):
        assert set(task) <= {'task_key', 'depends_on', 'sql_task'}
        sql = task['sql_task']
        assert sql['warehouse_id'] == '${var.warehouse_id}'
        assert sql['file'] == {'path': './' + filename, 'source': 'WORKSPACE'}
        assert sql['parameters'] == {
            **{key: '${var.' + key + '}' for key in
               ['catalog', 'bronze_schema', 'silver_schema', 'gold_schema', 'golden_path']},
            'drop': '{{job.parameters.drop}}'}
