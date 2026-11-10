CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.attribution')
USING DELTA
AS
SELECT CAST(tc.value:campaign_id AS STRING)  AS campaign_id,
       CAST(tc.value:channel AS STRING)      AS touch_channel,
       CAST(COUNT(*) AS BIGINT)              AS touches,
       CAST(COUNT(DISTINCT t.customer_id) AS BIGINT) AS customers_reached
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.campaign_touches') t,
       LATERAL variant_explode(parse_json(t.payload):touches) tc
GROUP  BY 1, 2;
