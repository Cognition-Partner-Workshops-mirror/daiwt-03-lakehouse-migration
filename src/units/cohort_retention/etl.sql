CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.cohort_retention') AS
WITH cohorts AS (
    SELECT customer_id,
           CAST(DATE_TRUNC('month', MIN(order_ts)) AS DATE) AS cohort_month
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders')
    GROUP BY customer_id
), activity AS (
    SELECT c.cohort_month,
           (YEAR(o.order_ts) * 12 + MONTH(o.order_ts))
             - (YEAR(c.cohort_month) * 12 + MONTH(c.cohort_month)) AS month_offset,
           COUNT(DISTINCT c.customer_id) AS active_buyers
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
    JOIN cohorts c ON c.customer_id = o.customer_id
    GROUP BY c.cohort_month,
             (YEAR(o.order_ts) * 12 + MONTH(o.order_ts))
               - (YEAR(c.cohort_month) * 12 + MONTH(c.cohort_month))
), sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohorts
    GROUP BY cohort_month
)
SELECT CAST(a.cohort_month AS DATE) AS cohort_month,
       CAST(a.month_offset AS INT) AS month_offset,
       CAST(s.cohort_size AS BIGINT) AS cohort_size,
       CAST(a.active_buyers AS BIGINT) AS active_buyers
FROM activity a
JOIN sizes s ON s.cohort_month = a.cohort_month;
