CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue') AS
SELECT CAST(o.order_ts AS DATE) AS order_date,
       CAST(o.sales_channel AS STRING) AS sales_channel,
       CAST(COUNT(DISTINCT o.order_id) AS BIGINT) AS order_count,
       CAST(SUM(oi.quantity * (oi.unit_price - oi.discount)) AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
  ON oi.order_id = o.order_id
GROUP BY 1, 2;
