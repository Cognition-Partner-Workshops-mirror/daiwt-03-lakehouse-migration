CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate') AS
WITH quantities AS (
  SELECT
    p.category,
    CAST(SUM(oi.quantity) AS BIGINT) AS sold_qty,
    CAST(COALESCE(SUM(r.quantity), 0) AS BIGINT) AS returned_qty
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
  JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
    ON p.product_id = oi.product_id
  LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.returns') r
    ON r.order_item_id = oi.order_item_id
  GROUP BY p.category
)
SELECT
  CAST(category AS STRING) AS category,
  CAST(sold_qty AS BIGINT) AS sold_qty,
  CAST(returned_qty AS BIGINT) AS returned_qty,
  CAST(returned_qty DIV sold_qty AS BIGINT) AS return_rate_int,
  CAST(CAST(FLOOR(CAST(returned_qty AS DECIMAL(14,4))
    / CAST(sold_qty AS DECIMAL(14,4)), 15) AS DECIMAL(29,15)) * 100 AS DECIMAL(33,15)) AS return_pct
FROM quantities;
