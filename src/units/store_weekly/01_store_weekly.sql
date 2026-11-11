CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.store_weekly') AS
SELECT
  CAST(o.store_id AS INT) AS store_id,
  CAST(date_trunc('week', o.order_ts) AS DATE) AS week_start,
  CAST(date_add(CAST(date_trunc('week', o.order_ts) AS DATE), 6) AS DATE) AS week_end,
  CAST(datediff(CAST(date_trunc('week', o.order_ts) AS DATE), DATE '2024-12-30') DIV 7 AS BIGINT) AS week_number,
  CAST(count(DISTINCT o.order_id) AS BIGINT) AS order_count,
  CAST(sum(oi.quantity * (oi.unit_price - oi.discount)) AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
  ON oi.order_id = o.order_id
GROUP BY o.store_id, date_trunc('week', o.order_ts);
