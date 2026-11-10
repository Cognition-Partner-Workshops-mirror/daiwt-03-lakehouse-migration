CREATE TEMPORARY VIEW order_items_candidates AS
SELECT order_item_id, order_id, product_id, quantity, unit_price, discount
FROM ${catalog}.${silver_schema}.asof_order_items(:drop)
UNION ALL
SELECT CAST(NULL AS BIGINT) AS order_item_id, CAST(-1 AS BIGINT) AS order_id, CAST(-1 AS INT) AS product_id,
       CAST(1 AS INT) AS quantity, CAST(0.00 AS DECIMAL(12,2)) AS unit_price, CAST(0.00 AS DECIMAL(12,2)) AS discount
WHERE '${silver_bad_rows}' = 'true'
UNION ALL
SELECT CAST(NULL AS BIGINT) AS order_item_id, CAST(NULL AS BIGINT) AS order_id, CAST(NULL AS INT) AS product_id,
       CAST(NULL AS INT) AS quantity, CAST(NULL AS DECIMAL(12,2)) AS unit_price, CAST(NULL AS DECIMAL(12,2)) AS discount
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW order_items (
  CONSTRAINT valid_key EXPECT (order_item_id IS NOT NULL) ON VIOLATION DROP ROW
)
AS SELECT order_item_id, order_id, product_id, quantity, unit_price, discount
FROM order_items_candidates;

CREATE OR REFRESH MATERIALIZED VIEW order_items_quarantine AS
SELECT *, 'null key' AS reason FROM order_items_candidates WHERE order_item_id IS NULL;
