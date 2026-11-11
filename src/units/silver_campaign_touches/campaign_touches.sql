CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.campaign_touches') AS
SELECT
  CAST(touch_id AS BIGINT) AS touch_id,
  CAST(customer_id AS BIGINT) AS customer_id,
  CAST(payload AS STRING) AS payload
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches')
WHERE _drop = :drop;
