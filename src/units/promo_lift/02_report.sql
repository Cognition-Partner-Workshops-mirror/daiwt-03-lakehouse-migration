CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_promo_lift') AS
SELECT
  CAST(sales_channel AS STRING) AS sales_channel,
  CAST(order_count AS BIGINT) AS order_count,
  CAST(median_order_value AS DECIMAL(38,2)) AS median_order_value,
  CAST(p90_order_value AS DECIMAL(38,2)) AS p90_order_value
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.promo_lift');
