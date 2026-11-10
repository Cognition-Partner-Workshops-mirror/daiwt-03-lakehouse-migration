# Databricks notebook source
import sys

root = dbutils.widgets.get('bundle_root')
sys.path.insert(0, root + '/src/sql/units/governance')
from governance import build_plan, load_metadata, mismatches, read_state, summary

catalog = dbutils.widgets.get('catalog')
schemas = {layer: dbutils.widgets.get(layer + '_schema') for layer in ('bronze', 'silver', 'gold')}
registry, contract = load_metadata(root)
tables, tags, columns = read_state(spark, catalog, schemas)
plans = build_plan(registry, contract, catalog, schemas, dbutils.widgets.get('data_owner'), tables)
action = dbutils.widgets.get('action')
notes = {}
failures = []
if action == 'apply':
    for plan in plans:
        for field, statement in plan['statements']:
            try:
                spark.sql(statement).collect()
            except Exception as error:
                condition = error.getCondition() if hasattr(error, 'getCondition') else ''
                if (plan['pipeline'] and field != 'tags'
                        and condition and ('NOT_SUPPORTED' in condition or 'UNSUPPORTED' in condition)):
                    notes.setdefault(plan['table'], []).append(field)
                    print(f"NOTE {plan['table']} {field}: {error}")
                else:
                    raise
        if plan['status'] != 'SKIP':
            plan['status'] = 'APPLIED (pipeline metadata note)' if plan['table'] in notes else 'APPLIED'
    dbutils.jobs.taskValues.set(key='pipeline_notes', value=notes)
elif action == 'check':
    notes = dbutils.jobs.taskValues.get(taskKey='apply_governance', key='pipeline_notes')
    for plan in plans:
        if plan['status'] == 'SKIP':
            continue
        exemptions = notes.get(plan['table'], []) if plan['pipeline'] else []
        missing = mismatches(plan, tables, tags, columns, exemptions)
        plan['status'] = 'FAIL: ' + ', '.join(missing) if missing else ('PASS (pipeline metadata note)' if exemptions else 'PASS')
        if missing:
            failures.append(f"{plan['table']}: {', '.join(missing)}")
else:
    raise ValueError(f'Unknown action: {action}')
markdown = summary(plans)
print(markdown)
dbutils.jobs.taskValues.set(key='summary', value=markdown)
if failures:
    raise RuntimeError('Governance check failed: ' + '; '.join(failures))
