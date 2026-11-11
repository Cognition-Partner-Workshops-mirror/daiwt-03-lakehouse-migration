CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.geo_rollup') AS
SELECT
  CAST(CASE
    WHEN GROUPING(s.region) = 0 AND GROUPING(s.state) = 1 THEN 1
    WHEN GROUPING(s.region) = 1 AND GROUPING(s.state) = 0 THEN 2
    ELSE 3
  END AS INT) AS grouping_id,
  CAST(s.region AS STRING) AS region,
  CAST(s.state AS STRING) AS state,
  CAST(COUNT(DISTINCT o.order_id) AS BIGINT) AS order_count,
  CAST(COALESCE(SUM(oi.quantity * (oi.unit_price - oi.discount)), 0) AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') s
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
  ON o.store_id = s.store_id
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
  ON oi.order_id = o.order_id
GROUP BY GROUPING SETS ((s.region), (s.state), ());
