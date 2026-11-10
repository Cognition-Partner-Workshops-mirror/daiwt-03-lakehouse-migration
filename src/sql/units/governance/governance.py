"""Registry-driven Unity Catalog metadata planning and verification."""
import json
from pathlib import Path


def identifier(value):
    return '`' + value.replace('`', '``') + '`'


def literal(value):
    return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\x00', '\\0') + "'"


def load_metadata(root):
    root = Path(root)
    registry = {path.parent.name: json.loads(path.read_text())
                for path in sorted((root / 'src/sql/units').glob('*/unit.json'))}
    return registry, json.loads((root / 'src/parity/contract.json').read_text())


def build_plan(registry, contract, catalog, schemas, owner, existing):
    """existing maps (physical schema, table) to information_schema table rows."""
    plans = []
    for unit, spec in sorted(registry.items()):
        for table in spec['outputs'] + spec['owns']:
            layer, name = table.split('.')
            schema = schemas[layer]
            if schema == 'landing':
                raise ValueError('landing is not a governance target')
            entries = [entry for entry in contract['outputs'] if entry['table'] == table]
            output = table in spec['outputs']
            if output and not entries:
                raise ValueError(f'No contract for {table}')
            kind = entries[0]['kind'] if output else 'owned'
            source = (f"report query of legacy unit {spec['legacy_unit']}"
                      if kind == 'report' else f"Redshift {'mart' if layer == 'gold' else 'core'}.{name}")
            comment = f"{layer.title()} {kind} {name}; legacy source: {source}; producing unit: {unit}."
            if output:
                comment += ' Parity-verified against golden: ' + ', '.join(sorted({entry['path'] for entry in entries})) + '.'
            tags = dict(source_system='redshift', medallion_layer=layer,
                        migration_unit=unit, legacy_unit=spec['legacy_unit'],
                        contract_kind=kind, owner_unit=unit, parity='golden' if output else 'none')
            columns = {}
            for entry in entries if output else []:
                for column in entry['columns']:
                    value = f"Legacy Redshift type: {column['redshift_type']}"
                    if column['name'] in columns and columns[column['name']] != value:
                        raise ValueError(f'Conflicting column contract for {table}')
                    columns[column['name']] = value
            row = existing.get((schema, name))
            plan = dict(table=table, schema=schema, name=name, unit=unit,
                        comment=comment, tags=tags, columns=columns, owner=owner,
                        status='APPLY' if row else 'SKIP', statements=[])
            if row:
                forms = {'MANAGED': 'TABLE', 'EXTERNAL': 'TABLE', 'VIEW': 'VIEW',
                         'MATERIALIZED_VIEW': 'MATERIALIZED VIEW', 'STREAMING_TABLE': 'STREAMING TABLE'}
                form = forms[row['table_type']]
                target = '.'.join(map(identifier, (catalog, schema, name)))
                plan['pipeline'] = row['table_type'] in ('MATERIALIZED_VIEW', 'STREAMING_TABLE')
                statements = [('comment', f"COMMENT ON {'VIEW' if form == 'VIEW' else 'TABLE'} {target} IS {literal(comment)}")]
                statements += [('column:' + column, f'COMMENT ON COLUMN {target}.{identifier(column)} IS {literal(value)}')
                               for column, value in columns.items()]
                statements += [('tags', f"ALTER {form} {target} SET TAGS (" + ', '.join(f'{literal(key)} = {literal(value)}' for key, value in tags.items()) + ')')]
                statements += [('owner', f'ALTER {form} {target} OWNER TO {identifier(owner)}')]
                plan['statements'] = statements
            plans.append(plan)
    return plans


def read_state(spark, catalog, schemas):
    prefix = identifier(catalog) + '.information_schema.'
    predicate = 'table_schema IN (' + ', '.join(literal(schema) for schema in schemas.values()) + ')'
    tables = {(row['table_schema'], row['table_name']): row.asDict()
              for row in spark.sql(f'SELECT * FROM {prefix}tables WHERE {predicate}').collect()}
    tags = {}
    tag_predicate = predicate.replace('table_schema', 'schema_name')
    for row in spark.sql(f'SELECT * FROM {prefix}table_tags WHERE {tag_predicate}').collect():
        tags.setdefault((row['schema_name'], row['table_name']), {})[row['tag_name']] = row['tag_value']
    columns = {}
    for row in spark.sql(f'SELECT * FROM {prefix}columns WHERE {predicate}').collect():
        columns.setdefault((row['table_schema'], row['table_name']), {})[row['column_name']] = row['comment']
    return tables, tags, columns


def mismatches(plan, tables, tags, columns, exemptions=()):
    key = (plan['schema'], plan['name'])
    row = tables[key]
    failures = []
    expected = {'comment': (row['comment'], plan['comment']),
                'owner': (row['table_owner'], plan['owner'])}
    expected.update({'column:' + name: (columns.get(key, {}).get(name), value)
                     for name, value in plan['columns'].items()})
    for field, (actual, value) in expected.items():
        if actual != value and field not in exemptions:
            failures.append(field)
    failures += ['tag:' + name for name, value in plan['tags'].items()
                 if tags.get(key, {}).get(name) != value]
    return failures


def summary(plans):
    return '| table | unit | status |\n| --- | --- | --- |\n' + '\n'.join(
        f"| {plan['table']} | {plan['unit']} | {plan['status']} |" for plan in plans)
