"""Fail-closed silver verification and gold publication gates."""
from parity.parity_check import GoldenStore, Warehouse, compare, contract_entries, identifier
from registry import tables, validate


def verify(client, registry, contract, catalog, schemas, warehouse_id, drop, mode, unit=''):
    validate(registry, contract)
    if mode == 'silver':
        expected = {table for spec in registry.values() for table in spec['outputs'] if table.startswith('silver.')}
        owned = {table for spec in registry.values() for table in tables(spec) if table.startswith('silver.')}
    elif mode == 'publish' and unit in registry:
        expected = {table for table in registry[unit]['outputs'] if table.startswith('gold.')}
        owned = set()
        if not expected:
            raise ValueError('Publication gate requires registered gold contract outputs')
    else:
        raise ValueError('Unknown gate mode or unit')
    warehouse = Warehouse(client, warehouse_id)

    def actual(entry):
        layer, name = entry['table'].split('.')
        target = '.'.join(identifier(part) for part in (catalog, schemas[layer], name))
        columns = ', '.join(
            f"date_format({identifier(column)}, 'yyyy-MM-dd HH:mm:ss') AS {identifier(column)}"
            if column in entry.get('timestamp_columns', []) else identifier(column) for column in entry['columns'])
        return warehouse.sql(f'SELECT {columns} FROM {target}')

    if expected:
        store = GoldenStore(client, '/Volumes/daiwt_03_mig_prod/landing/golden')
        entries = [entry for entry in contract_entries(contract, store.manifest(), drop) if entry['table'] in expected]
        if {entry['table'] for entry in entries} != expected:
            raise RuntimeError(f'Missing contract outputs for drop {drop}: {sorted(expected)}')
        result = compare({'tables': entries}, registry, store.rows, actual)
        if result['status'] != 'PASS' or any(row['status'] != 'PASS' for row in result['results']):
            raise RuntimeError(f'Strict parity gate failed: {result}')
    else:
        result = {'status': 'PASS', 'results': [], 'goldens': 0}
    for table in sorted(owned - expected):
        layer, name = table.split('.')
        target = '.'.join(identifier(part) for part in (catalog, schemas[layer], name))
        warehouse.sql(f'SELECT 1 FROM {target} LIMIT 0')
    return result
