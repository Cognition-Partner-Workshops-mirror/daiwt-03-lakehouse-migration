CREATE TEMPORARY VIEW payments_candidates AS
SELECT * FROM ${catalog}.${silver_schema}.asof_payments(:drop)
UNION ALL
SELECT CAST(NULL AS BIGINT), CAST(900000001 AS BIGINT), CAST('card' AS STRING),
  CAST(1.00 AS DECIMAL(12,2)), CAST('2025-01-01 00:00:00' AS TIMESTAMP_NTZ)
WHERE '${silver_bad_rows}' = 'true'
UNION ALL
SELECT CAST(NULL AS BIGINT), CAST(900000002 AS BIGINT), CAST(NULL AS STRING),
  CAST(2.00 AS DECIMAL(12,2)), CAST('2025-01-02 00:00:00' AS TIMESTAMP_NTZ)
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW payments (
  CONSTRAINT valid_key EXPECT (payment_id IS NOT NULL) ON VIOLATION DROP ROW
)
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT payment_id, order_id, method, amount, paid_ts FROM payments_candidates;

CREATE OR REFRESH MATERIALIZED VIEW payments_quarantine
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT *, 'null key' AS reason FROM payments_candidates WHERE payment_id IS NULL;
