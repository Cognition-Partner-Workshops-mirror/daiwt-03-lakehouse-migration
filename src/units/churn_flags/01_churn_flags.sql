CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.churn_flags') AS
WITH last_orders AS (
  SELECT
    c.customer_id,
    CAST(MAX(o.order_ts) AS DATE) AS last_order_date
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.customers') c
  LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
    ON o.customer_id = c.customer_id
  GROUP BY c.customer_id
)
SELECT
  CAST(customer_id AS BIGINT) AS customer_id,
  CAST(last_order_date AS DATE) AS last_order_date,
  CAST(datediff(DATE '2025-12-31', last_order_date) AS INT) AS days_since_order,
  CAST(CASE
    WHEN last_order_date IS NULL THEN 'never_ordered'
    WHEN datediff(DATE '2025-12-31', last_order_date) > 180 THEN 'churned'
    WHEN datediff(DATE '2025-12-31', last_order_date) > 90 THEN 'at_risk'
    ELSE 'active'
  END AS STRING) AS churn_flag
FROM last_orders;
