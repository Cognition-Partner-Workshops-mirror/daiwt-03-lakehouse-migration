CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_attribution') AS
SELECT
    CAST(campaign_id AS STRING) AS campaign_id,
    CAST(SUM(touches) AS BIGINT) AS touches,
    CAST(SUM(customers_reached) AS BIGINT) AS customers_reached
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.attribution')
GROUP BY campaign_id;
