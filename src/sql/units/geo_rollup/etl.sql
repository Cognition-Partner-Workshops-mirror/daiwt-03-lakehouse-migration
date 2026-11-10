-- geo_rollup: GROUPING SETS over region / store state. grouping_id keeps the
-- key unique across NULL grouping columns (1 = region, 2 = state, 3 = total).
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.geo_rollup')
USING DELTA
AS
WITH stores AS (
  SELECT store_id, rpad(rtrim(region), 4, ' ') AS region, state
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.stores')
)
SELECT CAST(CASE
         WHEN GROUPING(s.region) = 0 AND GROUPING(s.state) = 1 THEN 1
         WHEN GROUPING(s.region) = 1 AND GROUPING(s.state) = 0 THEN 2
         ELSE 3
       END AS INT)                           AS grouping_id,
       s.region,
       s.state,
       COUNT(DISTINCT o.order_id)            AS order_count,
       COALESCE(SUM(oi.quantity * (oi.unit_price - oi.discount)), 0) AS revenue
FROM   stores s
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.orders')      o  ON o.store_id = s.store_id
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi ON oi.order_id = o.order_id
GROUP  BY GROUPING SETS ((s.region), (s.state), ());
