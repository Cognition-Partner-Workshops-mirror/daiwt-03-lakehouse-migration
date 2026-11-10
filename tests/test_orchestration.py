import csv
import json
import sys
from decimal import Decimal, ROUND_DOWN, localcontext
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / 'src/sql/units/orchestration'
ETL = (UNIT / 'etl.sql').read_text()
REPORT = (UNIT / 'report.sql').read_text()


def summary_values(daily, customers, returns, shipping):
    def total(rows, column):
        values = [Decimal(row[column]) for row in rows if row[column] not in ('\\N', None)]
        return sum(values, Decimal(0)) if values else None

    def floor(value, scale):
        return value.quantize(Decimal(1).scaleb(-scale), rounding=ROUND_DOWN) if value is not None else None

    with localcontext() as context:
        context.prec = 80
        ltvs = [Decimal(row['ltv']) for row in customers if row['ltv'] not in ('\\N', None)]
        numerator = total(returns, 'returned_qty')
        denominator = total(returns, 'sold_qty')
        weighted = [dict(hours=Decimal(row['avg_hours_to_deliver']) * Decimal(row['delivered']))
                    for row in shipping if row['avg_hours_to_deliver'] not in ('\\N', None)
                    and row['delivered'] not in ('\\N', None)]
        delivered = total(shipping, 'delivered')
        hours = total(weighted, 'hours')
        return dict(snapshot_label='as_of_2025-12-31', as_of_date='2025-12-31',
                    total_revenue=floor(total(daily, 'revenue'), 2), total_orders=total(daily, 'order_count'),
                    avg_customer_ltv=floor(sum(ltvs) / len(ltvs), 2) if ltvs else None,
                    overall_return_pct=floor(floor(numerator, 4) / floor(denominator, 4), 15) * 100
                    if numerator is not None and denominator is not None else None,
                    avg_ship_hours=floor(hours / delivered, 4) if hours is not None and delivered is not None else None)


def test_job_sql_tasks():
    job = yaml.safe_load((UNIT / 'orchestration.job.yml').read_text())['resources']['jobs']['orchestration']
    assert job['name'] == '${var.job_name_prefix}orchestration'
    assert job['parameters'] == [{'name': 'drop', 'default': 'D0'}]
    assert job['tags'] == {'environment': '${bundle.target}'}
    assert [task['task_key'] for task in job['tasks']] == ['exec_summary', 'report']
    assert job['tasks'][1]['depends_on'] == [{'task_key': 'exec_summary'}]
    for task, filename in zip(job['tasks'], ['etl.sql', 'report.sql']):
        assert task['sql_task'] == dict(warehouse_id='${var.warehouse_id}',
            file={'path': './' + filename, 'source': 'WORKSPACE'},
            parameters=dict(catalog='${var.catalog}', gold_schema='${var.gold_schema}', drop='{{job.parameters.drop}}'))


def test_contract_and_sql_references():
    spec = json.loads((UNIT / 'unit.json').read_text())
    outputs = [entry for entry in json.loads((ROOT / 'src/parity/contract.json').read_text())['outputs']
               if entry['unit'] == spec['legacy_unit']]
    assert set(spec['outputs']) == {entry['table'] for entry in outputs}
    assert spec['job'] == 'orchestration' and spec['owns'] == []
    for dependency in spec['depends_on']:
        assert f"IDENTIFIER(:catalog || '.' || :gold_schema || '.{dependency}')" in ETL
    for table, sql in [('exec_summary', ETL), ('report_orchestration', REPORT)]:
        assert sql.startswith(f"CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.{table}')")
        assert 'BEGIN' not in sql and 'END;' not in sql
        assert 'daiwt_03' not in sql and 'current_date' not in sql.lower()
    assert "CAST('as_of_2025-12-31' AS VARCHAR(32))" in ETL
    assert "DATE '2025-12-31'" in ETL
    assert 'CASE WHEN ltv.avg_ltv < 0 THEN -FLOOR(-ltv.avg_ltv, 2) ELSE FLOOR(ltv.avg_ltv, 2) END' in ETL
    assert 'FLOOR(rr.return_ratio, 15) AS DECIMAL(29,15)' in ETL
    assert '* CAST(100 AS DECIMAL(3,0)) AS DECIMAL(38,15))' in ETL
    assert 'CASE WHEN sla.avg_hours_to_deliver < 0 THEN -FLOOR(-sla.avg_hours_to_deliver, 4) ELSE FLOOR(sla.avg_hours_to_deliver, 4) END' in ETL
    assert 'ORDER BY snapshot_label' in REPORT
    for column in outputs[0]['columns']:
        assert column['name'] in ETL and column['name'] in REPORT


def test_decimal_truncation_and_nulls():
    result = summary_values([dict(revenue='10.01', order_count='2')],
                            [dict(ltv='1.00'), dict(ltv='2.99'), dict(ltv='\\N')],
                            [dict(returned_qty='1', sold_qty='3')],
                            [dict(avg_hours_to_deliver='1.00', delivered='1'),
                             dict(avg_hours_to_deliver='2.00', delivered='2')])
    assert str(result['avg_customer_ltv']) == '1.99'
    assert str(result['overall_return_pct']) == '33.333333333333300'
    assert str(result['avg_ship_hours']) == '1.6666'
    assert result['total_revenue'] == Decimal('10.01') and result['total_orders'] == 2
    assert all(value is None for key, value in summary_values([], [], [], []).items()
               if key not in ('snapshot_label', 'as_of_date'))
    with pytest.raises(ArithmeticError):
        summary_values([], [], [dict(returned_qty='1', sold_qty='0')], [])


def check_goldens(root):
    def read(unit, table):
        with (root / unit / (table + '.csv')).open() as stream:
            return list(csv.DictReader(stream))

    result = summary_values(*(read(unit, unit) for unit in
                              ('daily_revenue', 'customer_ltv', 'returns_rate', 'shipping_sla')))
    expected = read('orchestration', 'exec_summary')[0]
    report = read('orchestration', 'report')[0]
    for column, actual in result.items():
        rendered = '\\N' if actual is None else str(actual)
        print(f'{column}: computed={rendered} golden={expected[column]} ' +
              ('PASS' if rendered == expected[column] == report[column] else 'FAIL'))
        assert rendered == expected[column] == report[column]


if __name__ == '__main__':
    check_goldens(Path(sys.argv[1]))
