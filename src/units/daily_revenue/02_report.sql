CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue_report') AS
SELECT CAST(DATE_TRUNC('month', order_date) AS DATE) AS order_month,
       CAST(sales_channel AS STRING) AS sales_channel,
       CAST(SUM(order_count) AS BIGINT) AS order_count,
       CAST(SUM(revenue) AS DECIMAL(38, 2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue')
GROUP BY 1, 2;
