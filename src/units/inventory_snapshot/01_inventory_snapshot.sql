CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.inventory_snapshot') AS
WITH sales AS (
  SELECT
    product_id,
    CAST(SUM(quantity) AS BIGINT) AS units_sold
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items')
  GROUP BY product_id
)
SELECT
  CAST(p.product_id AS INT) AS product_id,
  CAST('2025-12-31' AS DATE) AS snapshot_date,
  CAST(COALESCE(s.units_sold, 0) AS BIGINT) AS units_sold,
  CAST(GREATEST(500 - COALESCE(s.units_sold, 0), 0) AS INT) AS on_hand
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.products') AS p
LEFT JOIN sales AS s ON s.product_id = p.product_id;
