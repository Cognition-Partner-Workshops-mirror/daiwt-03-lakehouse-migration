CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv') AS
SELECT
  CAST(c.customer_id AS BIGINT) AS customer_id,
  CAST(c.region AS STRING) AS region,
  CAST(regexp_replace(c.phone, '[^0-9]', '') AS STRING) AS clean_phone,
  CAST(COUNT(DISTINCT o.order_id) AS BIGINT) AS order_count,
  CAST(COALESCE(SUM(oi.quantity * (oi.unit_price - oi.discount)), 0) AS DECIMAL(38,2)) AS ltv,
  CAST(SIGN(AVG(oi.unit_price - oi.discount))
    * FLOOR(ABS(AVG(oi.unit_price - oi.discount)), 2) AS DECIMAL(38,2)) AS aov
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.customers') c
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
  ON o.customer_id = c.customer_id
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
  ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.region, c.phone;
