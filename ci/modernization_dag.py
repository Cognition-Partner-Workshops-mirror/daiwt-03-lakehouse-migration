"""Generate the modernization job from registered units and bundle resources."""
import argparse
from pathlib import Path

import yaml

from registry import load, tables, topo_order

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = 'resources/modernization.job.yml'


def bundle_resources(root):
    root = Path(root)
    bundle = yaml.safe_load((root / 'databricks.yml').read_text())
    resources = {}
    for pattern in bundle['include']:
        for path in sorted(root.glob(pattern)):
            if path == root / DESTINATION:
                continue
            document = yaml.safe_load(path.read_text()) or {}
            for kind, entries in document.get('resources', {}).items():
                resources.setdefault(kind, {}).update(entries)
    return resources


def generate(registry, resources):
    order = topo_order(registry, '*')
    jobs = resources.get('jobs', {})
    pipelines = resources.get('pipelines', {})
    runnable = {unit for unit in order if registry[unit]['job'] in jobs or registry[unit]['job'] in pipelines}
    runnable.discard('governance')
    gold = {unit for unit in runnable if any(table.startswith('gold.') for table in tables(registry[unit]))}
    silver = {unit for unit in runnable if any(table.startswith('silver.') for table in tables(registry[unit]))}
    if gold & silver:
        raise ValueError('Split mixed silver/gold producers before inserting the silver gate')
    reserved = {'verify_silver', 'governance'} | {'publish_' + unit for unit in gold}
    if runnable & reserved:
        raise ValueError('Registry unit collides with a gate task key')

    def dependencies(unit):
        result = set()
        for dependency in registry[unit]['depends_on']:
            if dependency == 'governance':
                raise ValueError('Governance must be terminal')
            if dependency in runnable:
                result.add(dependency)
            else:
                result.update(dependencies(dependency))
        return result

    def gate(key, mode, units, deps):
        return dict(task_key=key, depends_on=[{'task_key': dep} for dep in sorted(deps)],
                    notebook_task=dict(notebook_path='../src/modernization/gate_task.py', base_parameters={
                        'bundle_root': '${workspace.file_path}', 'catalog': '${var.catalog}',
                        'bronze_schema': '${var.bronze_schema}', 'silver_schema': '${var.silver_schema}',
                        'gold_schema': '${var.gold_schema}', 'warehouse_id': '${var.warehouse_id}',
                        'drop': '{{job.parameters.drop}}', 'mode': mode, 'unit': units}))

    tasks = []
    for unit in order:
        if unit not in runnable:
            continue
        key = registry[unit]['job']
        deps = dependencies(unit)
        if unit in gold:
            deps.add('verify_silver')
        task = dict(task_key=unit)
        if deps:
            task['depends_on'] = [{'task_key': dep} for dep in sorted(deps)]
        if key in jobs:
            task['run_job_task'] = dict(job_id='${resources.jobs.' + key + '.id}',
                                       job_parameters={'drop': '{{job.parameters.drop}}'})
        else:
            task['pipeline_task'] = dict(pipeline_id='${resources.pipelines.' + key + '.id}',
                                         full_refresh=True, parameters={'drop': '{{job.parameters.drop}}'})
        tasks.append(task)
    tasks.append(gate('verify_silver', 'silver', '', runnable - gold))
    for unit in order:
        if unit in gold and any(table.startswith('gold.') for table in registry[unit]['outputs']):
            tasks.append(gate('publish_' + unit, 'publish', unit, {unit}))
    governance = registry.get('governance', {}).get('job')
    if governance not in jobs:
        raise ValueError('A governance job resource is required')
    tasks.append(dict(task_key='governance', run_if='NONE_FAILED',
                      depends_on=[{'task_key': task['task_key']} for task in tasks],
                      run_job_task=dict(job_id='${resources.jobs.' + governance + '.id}',
                                        job_parameters={'drop': '{{job.parameters.drop}}'})))
    graph = {task['task_key']: {'depends_on': [dep['task_key'] for dep in task.get('depends_on', [])]}
             for task in tasks}
    topo_order(graph, '*')
    job = dict(name='${var.job_name_prefix}modernization', max_concurrent_runs=1,
               parameters=[dict(name='drop', default='D0')], tags={'environment': '${bundle.target}'},
               schedule=dict(quartz_cron_expression='0 0 2 * * ?', timezone_id='UTC', pause_status='PAUSED'),
               tasks=tasks)
    return {'resources': {'jobs': {'modernization': job}}, 'targets': {
        target: {'resources': {'jobs': {'modernization': {'schedule': {'pause_status': pause}}}}}
        for target, pause in [('dev', 'PAUSED'), ('prod', 'UNPAUSED')]}}


def render(root=ROOT):
    return yaml.safe_dump(generate(load(root), bundle_resources(root)), sort_keys=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    content = render()
    destination = ROOT / DESTINATION
    if args.check:
        if destination.read_text() != content:
            raise SystemExit('Regenerate resources/modernization.job.yml: python ci/modernization_dag.py')
    else:
        destination.write_text(content)
