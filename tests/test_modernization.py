from pathlib import Path

import pytest
import yaml

from modernization_dag import DESTINATION, bundle_resources, generate, render
from modernization import gates
from registry import load

ROOT = Path(__file__).resolve().parents[1]


def spec(job, outputs=(), owns=(), deps=()):
    return dict(job=job, legacy_unit='source', outputs=list(outputs), owns=list(owns), depends_on=list(deps))


def test_committed_dag_matches_registry():
    assert (ROOT / DESTINATION).read_text() == render(ROOT)


def test_generic_jobs_pipeline_and_gates():
    registry = {'raw': spec('load_job', owns=['bronze.x']),
                'helper': spec('missing', deps=['raw']),
                'typed': spec('typed_pipeline', outputs=['silver.x'], deps=['helper']),
                'mart': spec('mart_job', outputs=['gold.x'], deps=['typed']),
                'report': spec('report_job', outputs=['gold.report'], deps=['mart']),
                'governance': spec('governance_job')}
    resources = {'jobs': dict.fromkeys(['load_job', 'mart_job', 'report_job', 'governance_job']),
                 'pipelines': {'typed_pipeline': {}}}
    document = generate(registry, resources)
    job = document['resources']['jobs']['modernization']
    tasks = {task['task_key']: task for task in job['tasks']}
    assert 'helper' not in tasks
    assert tasks['typed']['pipeline_task'] == {'pipeline_id': '${resources.pipelines.typed_pipeline.id}',
                                               'full_refresh': True, 'parameters': {'drop': '{{job.parameters.drop}}'}}
    assert tasks['typed']['depends_on'] == [{'task_key': 'raw'}]
    assert tasks['mart']['run_job_task'] == {'job_id': '${resources.jobs.mart_job.id}',
                                           'job_parameters': {'drop': '{{job.parameters.drop}}'}}
    assert tasks['mart']['depends_on'] == [{'task_key': 'typed'}, {'task_key': 'verify_silver'}]
    assert tasks['report']['depends_on'] == [{'task_key': 'mart'}, {'task_key': 'verify_silver'}]
    assert tasks['publish_mart']['depends_on'] == [{'task_key': 'mart'}]
    assert tasks['publish_report']['notebook_task']['base_parameters']['unit'] == 'report'
    assert {dep['task_key'] for dep in tasks['verify_silver']['depends_on']} == {'raw', 'typed'}
    assert {dep['task_key'] for dep in tasks['governance']['depends_on']} == tasks.keys() - {'governance'}
    assert tasks['governance']['run_if'] == 'NONE_FAILED'
    assert job['max_concurrent_runs'] == 1
    assert job['schedule']['quartz_cron_expression'] == '0 0 2 * * ?'
    assert job['schedule']['timezone_id'] == 'UTC'
    assert document['targets']['dev']['resources']['jobs']['modernization']['schedule']['pause_status'] == 'PAUSED'
    assert document['targets']['prod']['resources']['jobs']['modernization']['schedule']['pause_status'] == 'UNPAUSED'
    for task in tasks.values():
        assert not any('cluster' in key for key in task)


def test_empty_registry_and_invalid_graphs():
    resources = {'jobs': {'gov': {}}}
    registry = {'governance': spec('gov')}
    tasks = generate(registry, resources)['resources']['jobs']['modernization']['tasks']
    assert [task['task_key'] for task in tasks] == ['verify_silver', 'governance']
    with pytest.raises(ValueError, match='governance job'):
        generate({}, {})
    registry['mixed'] = spec('mixed', ['silver.x', 'gold.x'])
    resources['jobs']['mixed'] = {}
    with pytest.raises(ValueError, match='mixed silver/gold'):
        generate(registry, resources)


def test_silver_wrapper_and_future_entity_checks_precede_gate():
    registry = load(ROOT)
    resources = bundle_resources(ROOT)
    registry['silver_example'] = spec('silver_example', outputs=['silver.example'],
                                      deps=['silver_pipeline', 'silver_asof'])
    registry['mart_example'] = spec('mart_example', outputs=['gold.example'], deps=['silver_example'])
    resources['jobs'].update(silver_example={}, mart_example={})
    tasks = {task['task_key']: task for task in generate(registry, resources)['resources']['jobs']['modernization']['tasks']}
    assert tasks['silver_pipeline']['run_job_task'] == {
        'job_id': '${resources.jobs.silver_pipeline.id}', 'job_parameters': {'drop': '{{job.parameters.drop}}'}}
    assert tasks['silver_pipeline']['depends_on'] == [{'task_key': 'silver_asof'}]
    assert tasks['silver_asof']['depends_on'] == [{'task_key': 'bronze_landing'}]
    assert tasks['silver_example']['depends_on'] == [{'task_key': 'silver_asof'}, {'task_key': 'silver_pipeline'}]
    assert {'task_key': 'silver_example'} in tasks['verify_silver']['depends_on']
    assert {'task_key': 'silver_pipeline'} in tasks['verify_silver']['depends_on']
    assert tasks['mart_example']['depends_on'] == [{'task_key': 'silver_example'}, {'task_key': 'verify_silver'}]
    wrapper = resources['jobs']['silver_pipeline']
    refresh = wrapper['tasks'][0]['pipeline_task']
    assert refresh == {'pipeline_id': '${resources.pipelines.silver.id}', 'full_refresh': True,
                       'parameters': {'drop': '{{job.parameters.drop}}'}}
    assert wrapper['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    assert registry['silver_pipeline']['outputs'] == registry['silver_pipeline']['owns'] == []


class Warehouse:
    def __init__(self, rows):
        self.rows = rows
        self.queries = []

    def sql(self, query):
        self.queries.append(query)
        return self.rows


def setup_gate(monkeypatch, rows):
    warehouse = Warehouse(rows)
    monkeypatch.setattr(gates, 'Warehouse', lambda *_: warehouse)
    class Store:
        def __init__(self, *_):
            pass

        def manifest(self):
            return {}

        def rows(self, entry):
            return [['1']]

    monkeypatch.setattr(gates, 'GoldenStore', Store)
    return warehouse


def test_silver_fallback_and_empty_registry(monkeypatch):
    warehouse = setup_gate(monkeypatch, [['1']])
    registry = {'typed': spec('typed', owns=['silver.x'])}
    contract = {'outputs': [{'table': 'gold.other', 'unit': 'source'}]}
    args = (None, registry, contract, 'catalog', {'silver': 'silver_pr_1'}, 'warehouse', 'D0', 'silver')
    assert gates.verify(*args)['status'] == 'PASS'
    assert warehouse.queries == ['SELECT 1 FROM `catalog`.`silver_pr_1`.`x` LIMIT 1']
    warehouse.rows = []
    with pytest.raises(RuntimeError, match='Silver output is empty'):
        gates.verify(*args)
    assert gates.verify(None, {}, {'outputs': []}, 'catalog', {}, 'w', 'D0', 'silver')['status'] == 'PASS'


@pytest.mark.parametrize('mode,table', [('silver', 'silver.x'), ('publish', 'gold.x')])
def test_strict_parity_scopes_to_outputs_and_rejects_mismatches(monkeypatch, mode, table):
    warehouse = setup_gate(monkeypatch, [['1']])
    registry = {'producer': spec('producer', outputs=[table]),
                'other': spec('other', outputs=['gold.other'])}
    contract = {'outputs': [{'table': table, 'unit': 'source'}, {'table': 'gold.other', 'unit': 'source'}]}
    entries = [{'table': table, 'columns': ['id']}, {'table': 'gold.other', 'columns': ['id']}]
    monkeypatch.setattr(gates, 'contract_entries', lambda *_: entries)
    args = (None, registry, contract, 'catalog', {'silver': 's', 'gold': 'g'}, 'w', 'D0', mode, 'producer')
    result = gates.verify(*args)
    assert result['status'] == 'PASS' and len(result['results']) == 1
    assert len(warehouse.queries) == 1
    warehouse.rows = [['2']]
    with pytest.raises(RuntimeError, match='Strict parity gate failed'):
        gates.verify(*args)
    entries.clear()
    with pytest.raises(RuntimeError, match='Missing contract outputs'):
        gates.verify(*args)


def test_gate_propagates_read_failure_and_invalid_mode(monkeypatch):
    setup_gate(monkeypatch, [])
    with pytest.raises(ValueError, match='Unknown gate'):
        gates.verify(None, {}, {'outputs': []}, 'c', {}, 'w', 'D0', 'invalid')
    monkeypatch.setattr(gates, 'Warehouse', lambda *_: (_ for _ in ()).throw(RuntimeError('denied')))
    with pytest.raises(RuntimeError, match='denied'):
        gates.verify(None, {}, {'outputs': []}, 'c', {}, 'w', 'D0', 'silver')


def test_workflow_runs_modernization_and_retains_oidc():
    workflow = yaml.safe_load((ROOT / '.github/workflows/deploy-prod.yml').read_text())
    job = workflow['jobs']['deploy']
    assert job['env']['DATABRICKS_AUTH_TYPE'] == 'github-oidc'
    commands = '\n'.join(step.get('run', '') for step in job['steps'])
    assert 'databricks bundle run -t prod --params "drop=$drop" modernization' in commands
    assert 'python ci/run_units.py prod' not in commands
    assert commands.index('bundle deploy') < commands.index('bundle run')
    assert "test '${{ steps.parity.outcome }}' = success" in commands
