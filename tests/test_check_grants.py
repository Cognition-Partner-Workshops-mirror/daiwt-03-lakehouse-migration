from types import SimpleNamespace
from pathlib import Path

import pytest
import yaml

from check_grants import SCHEMA_REQUIRED, check, effective_assignments, evaluate_job, evaluate_uc, markdown


def acl(**kwargs):
    level = kwargs.pop('level')
    return {**kwargs, 'all_permissions': [{'permission_level': level, 'inherited': True}]}


@pytest.mark.parametrize('manager_field', ['service_principal_name', 'user_name', 'group_name'])
@pytest.mark.parametrize('level', ['CAN_MANAGE', 'IS_OWNER'])
def test_job_effective_acl(manager_field, level):
    permissions = {'access_control_list': [acl(group_name='users', level='CAN_VIEW'),
                                           acl(**{manager_field: 'deployer'}, level=level)]}
    assert evaluate_job(permissions, 'deployer', {'deployer'}) == []


def test_job_missing_and_insufficient_access():
    assert len(evaluate_job({}, 'deployer')) == 2
    permissions = {'access_control_list': [acl(group_name='users', level='CAN_VIEW'),
                                           acl(user_name='other', level='IS_OWNER'),
                                           acl(service_principal_name='deployer', level='CAN_MANAGE_RUN')]}
    assert evaluate_job(permissions, 'deployer') == ['deployer CAN_MANAGE or IS_OWNER']


def assignment(principal, privileges):
    return {'principal': principal, 'privileges': [dict(privilege=privilege, inherited_from_name='catalog')
                                                for privilege in privileges]}


def test_uc_inheritance_group_owner_and_equivalent():
    assert evaluate_uc([assignment('deployer', ['ALL_PRIVILEGES'])], 'deployer', set(), SCHEMA_REQUIRED) == []
    assert evaluate_uc([assignment('team', SCHEMA_REQUIRED)], 'deployer', {'team'}, SCHEMA_REQUIRED) == []
    assert evaluate_uc([], 'deployer', set(), SCHEMA_REQUIRED, owner='deployer') == []
    assert evaluate_uc([], 'deployer', {'team'}, SCHEMA_REQUIRED, owner='team') == []
    assert evaluate_uc([assignment('other', ['ALL_PRIVILEGES'])], 'deployer', set(), {'USE_CATALOG'}) == ['USE_CATALOG']
    assert evaluate_uc([], 'deployer', set(), SCHEMA_REQUIRED) == sorted(SCHEMA_REQUIRED)
    assert evaluate_uc([assignment('deployer', SCHEMA_REQUIRED - {'MODIFY'})], 'deployer', set(), SCHEMA_REQUIRED) == ['MODIFY']


def test_effective_api_paginates_empty_pages():
    calls = []
    def get_effective(kind, name, **kwargs):
        calls.append((kind, name, kwargs))
        return SimpleNamespace(privilege_assignments=[], next_page_token='next' if len(calls) == 1 else None)
    client = SimpleNamespace(grants=SimpleNamespace(get_effective=get_effective))
    assert effective_assignments(client, 'schema', 'catalog.silver') == []
    assert calls[-1][-1] == dict(max_results=0, page_token='next')


def test_missing_job_ids_fail_and_api_errors_are_reported():
    client = SimpleNamespace(current_user=SimpleNamespace(me=lambda: SimpleNamespace(user_name='deployer', groups=[])),
                             grants=SimpleNamespace(get_effective=lambda *a, **kw: (_ for _ in ()).throw(RuntimeError('denied'))))
    variables = {key: {'value': value} for key, value in dict(catalog='catalog', bronze_schema='bronze',
                 silver_schema='silver', gold_schema='gold').items()}
    rows = check(client, {'resources': {'jobs': {'x': {}}}, 'variables': variables})
    assert len(rows) == 5 and all(row[1] == 'FAIL' for row in rows)
    assert rows[0][-1] == 'No deployed job ID resolved'
    assert rows[-1][-1] == 'denied'
    assert markdown([('a|b', 'FAIL', 'line\nnext')]).endswith('| a\\|b | FAIL | line next |')


def test_reads_actual_acl_and_ownership():
    class Response:
        def as_dict(self):
            return {'access_control_list': [acl(group_name='users', level='CAN_VIEW'),
                                           acl(service_principal_name='deployer', level='IS_OWNER')]}
    ids = []
    def get_permissions(job_id):
        ids.append(job_id)
        return Response()
    client = SimpleNamespace(
        current_user=SimpleNamespace(me=lambda: SimpleNamespace(user_name='deployer', groups=[])),
        jobs=SimpleNamespace(get_permissions=get_permissions),
        grants=SimpleNamespace(get_effective=lambda *a, **kw: SimpleNamespace(privilege_assignments=[], next_page_token=None)),
        catalogs=SimpleNamespace(get=lambda _: SimpleNamespace(owner='deployer')),
        schemas=SimpleNamespace(get=lambda _: SimpleNamespace(owner='deployer')))
    summary = {'resources': {'jobs': {'job': {'id': 123}}},
               'variables': {key: {'value': value} for key, value in dict(catalog='catalog',
                   bronze_schema='b', silver_schema='s', gold_schema='g').items()}}
    rows = check(client, summary)
    assert ids == ['123'] and len(rows) == 5
    assert all(row[1] == 'PASS' for row in rows)
    summary['resources']['jobs'] = {}
    assert check(client, summary)[0][1] == 'FAIL'


def test_last_workflow_step_checks_grants():
    root = Path(__file__).resolve().parents[1]
    workflow = yaml.safe_load((root / '.github/workflows/deploy-prod.yml').read_text())
    assert workflow['jobs']['deploy']['steps'][-1] == dict(
        name='Check deployed grants', **{'if': 'always()'}, run='python ci/check_grants.py --target prod')
