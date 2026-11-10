# Databricks notebook source
import json
import sys
from pathlib import Path

root = Path(dbutils.widgets.get('bundle_root'))
sys.path[:0] = [str(root / 'src'), str(root / 'ci')]
from databricks.sdk import WorkspaceClient
from modernization.gates import verify
from registry import load

result = verify(WorkspaceClient(), load(root),
                json.loads((root / 'src/parity/contract.json').read_text()),
                dbutils.widgets.get('catalog'),
                {layer: dbutils.widgets.get(layer + '_schema') for layer in ('bronze', 'silver', 'gold')},
                dbutils.widgets.get('warehouse_id'), dbutils.widgets.get('drop'),
                dbutils.widgets.get('mode'), dbutils.widgets.get('unit'))
print(json.dumps(result, indent=2))
dbutils.jobs.taskValues.set(key='parity', value=result)
