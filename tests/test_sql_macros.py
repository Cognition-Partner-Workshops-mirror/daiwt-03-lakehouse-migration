import json
import re
from datetime import date
from pathlib import Path

import pytest
import yaml

from registry import load, validate

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/sql_macros'
FUNCTIONS = (UNIT / 'functions.sql').read_text()
CHECKS = (UNIT / 'self_check.sql').read_text()


def fiscal_quarter(d):
    return None if d is None else 'Q' + str((((d.month + 9) % 12) // 3) + 1)


def clean_phone(p):
    return None if p is None else re.sub('[^0-9]', '', p)


def test_registry_schema():
    registry = load(ROOT)
    spec = json.loads((UNIT / 'unit.json').read_text())
    assert registry['sql_macros'] == spec
    assert spec == dict(job='sql_macros', legacy_unit='foundation', outputs=[], owns=[], depends_on=[])
    validate({'sql_macros': spec}, json.loads((ROOT / 'src/parity/contract.json').read_text()))


def test_job_sql_file_tasks():
    resource = yaml.safe_load((UNIT / 'sql_macros.job.yml').read_text())
    assert set(resource['resources']['jobs']) == {'sql_macros'}
    job = resource['resources']['jobs']['sql_macros']
    assert job['name'] == '${var.job_name_prefix}sql_macros'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    assert job['tags']['environment'] == '${bundle.target}'
    tasks = job['tasks']
    assert [t['task_key'] for t in tasks] == ['create_functions', 'check_functions']
    assert 'depends_on' not in tasks[0]
    assert tasks[1]['depends_on'] == [{'task_key': 'create_functions'}]
    for task, filename in zip(tasks, ['functions.sql', 'self_check.sql']):
        assert set(task) <= {'task_key', 'depends_on', 'sql_task'}
        sql = task['sql_task']
        assert sql['warehouse_id'] == '${var.warehouse_id}'
        assert sql['file'] == {'path': './' + filename, 'source': 'WORKSPACE'}
        assert (UNIT / sql['file']['path']).is_file()
        assert sql['parameters'] == {
            'catalog': '${var.catalog}', 'bronze_schema': '${var.bronze_schema}',
            'silver_schema': '${var.silver_schema}', 'gold_schema': '${var.gold_schema}',
            'drop': '{{job.parameters.drop}}'}
    # Permissions come from the target, never a hard-coded run identity.
    assert 'permissions' not in job and 'run_as' not in job


def test_fiscal_self_check_has_exact_integer_arithmetic_table():
    cases = [(int(month), expected) for month, expected in re.findall(r"\((\d+), '(Q[1-4])'\)", CHECKS)]
    expected = ['Q4', 'Q4', 'Q1', 'Q1', 'Q1', 'Q2', 'Q2', 'Q2', 'Q3', 'Q3', 'Q3', 'Q4']
    assert cases == list(enumerate(expected, 1))
    assert [fiscal_quarter(date(2025, month, 1)) for month in range(1, 13)] == expected
    assert fiscal_quarter(None) is None
    assert "RETURN 'Q' || CAST((((month(d) + 9) % 12) DIV 3) + 1 AS STRING)" in FUNCTIONS
    assert '(CAST(NULL AS INT), CAST(NULL AS STRING))' in CHECKS


@pytest.mark.parametrize('phone,expected', re.findall(r"\('([^']*)', '([^']*)'\)", CHECKS))
def test_phone_self_check_cases(phone, expected):
    assert clean_phone(phone) == expected


def test_phone_null_empty_and_ascii_only():
    assert clean_phone(None) is None
    assert clean_phone('') == ''
    assert clean_phone(' ()-+./abc') == ''
    assert clean_phone('abc١۲３45') == '45'
    assert "RETURN regexp_replace(p, '[^0-9]', '')" in FUNCTIONS
    assert '(CAST(NULL AS STRING), CAST(NULL AS STRING))' in CHECKS


def test_checks_are_fail_closed_and_use_parameterized_function_names():
    for name, argument, signature in [('f_fiscal_qtr', 'd', 'DATE'), ('f_clean_phone', 'p', 'STRING')]:
        target = "IDENTIFIER(:catalog || '.' || :silver_schema || '." + name + "')"
        assert 'CREATE OR REPLACE FUNCTION ' + target + f'({argument} {signature})' in FUNCTIONS
        assert target + '(' in CHECKS
        assert f"raise_error('{name} semantics drift')" in CHECKS
    assert FUNCTIONS.count('RETURNS STRING\nDETERMINISTIC') == 2
    assert CHECKS.count('count_if(NOT (actual <=> expected)) = 0') == 2
    assert 'count(*) = 13' in CHECKS and 'count(*) = 7' in CHECKS
    assert 'daiwt_03_' not in FUNCTIONS + CHECKS
