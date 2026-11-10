CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_promo_lift')
USING DELTA
AS
SELECT sales_channel, order_count, median_order_value, p90_order_value
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.promo_lift');
