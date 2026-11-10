CREATE TEMPORARY VIEW orders_candidates AS
SELECT order_id, customer_id, store_id, order_ts, sales_channel, status
FROM ${catalog}.${silver_schema}.asof_orders(:drop)
UNION ALL
SELECT CAST(NULL AS BIGINT) AS order_id, CAST(900000001 AS BIGINT) AS customer_id,
       CAST(1 AS INT) AS store_id, CAST(TIMESTAMP_NTZ'2025-01-01 00:00:00' AS TIMESTAMP_NTZ) AS order_ts,
       CAST('web' AS STRING) AS sales_channel, CAST('complete' AS STRING) AS status
WHERE '${silver_bad_rows}' = 'true'
UNION ALL
SELECT CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS INT),
       CAST(NULL AS TIMESTAMP_NTZ), CAST(NULL AS STRING), CAST(NULL AS STRING)
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW orders (
  CONSTRAINT valid_order_id EXPECT (order_id IS NOT NULL) ON VIOLATION DROP ROW
)
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT order_id, customer_id, store_id, order_ts, sales_channel, status
FROM orders_candidates;

CREATE OR REFRESH MATERIALIZED VIEW orders_quarantine
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT order_id, customer_id, store_id, order_ts, sales_channel, status,
          'null order_id' AS reason
FROM orders_candidates
WHERE order_id IS NULL;
