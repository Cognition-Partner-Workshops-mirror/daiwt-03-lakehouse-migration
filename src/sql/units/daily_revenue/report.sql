CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_daily_revenue')
USING DELTA
AS
SELECT CAST(DATE_TRUNC('MONTH', order_date) AS DATE)  AS order_month,
       sales_channel,
       CAST(SUM(order_count) AS BIGINT)               AS order_count,
       CAST(SUM(revenue) AS DECIMAL(38,2))            AS revenue
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue')
GROUP  BY 1, 2;
