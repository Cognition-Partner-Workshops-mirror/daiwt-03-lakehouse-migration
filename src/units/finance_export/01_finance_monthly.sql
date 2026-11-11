CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.finance_monthly') AS
WITH order_dates AS (
  SELECT order_id, CAST(order_ts AS DATE) AS d
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders')
)
SELECT
  CAST(date_trunc('month', o.d) AS DATE) AS month,
  CAST(CASE WHEN month(o.d) >= 2 THEN year(o.d) ELSE year(o.d) - 1 END AS INT) AS fiscal_year,
  CAST(concat('Q', cast((((month(d)+9)%12) DIV 3)+1 as string)) AS STRING) AS fiscal_qtr,
  CAST(count(DISTINCT o.order_id) AS BIGINT) AS order_count,
  CAST(sum(oi.quantity * (oi.unit_price - oi.discount)) AS DECIMAL(38,2)) AS revenue
FROM order_dates o
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
  ON oi.order_id = o.order_id
GROUP BY 1, 2, 3;
