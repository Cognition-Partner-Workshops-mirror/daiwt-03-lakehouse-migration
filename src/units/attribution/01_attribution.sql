CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.attribution') AS
WITH payloads AS (
  SELECT
    customer_id,
    payload,
    CAST(json_array_length(get_json_object(payload, '$.touches')) AS INT) AS touch_count
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.campaign_touches')
), touches AS (
  SELECT
    t.customer_id,
    substring(get_json_object(payload, (concat('$.touches[', CAST(touch_index AS STRING), '].campaign_id'))), 1, 16) AS campaign_id,
    substring(get_json_object(payload, (concat('$.touches[', CAST(touch_index AS STRING), '].channel'))), 1, 16) AS touch_channel
  FROM payloads AS t
  -- Expand only populated arrays; missing, null and empty arrays have no touches.
  LATERAL VIEW explode(sequence(0, touch_count - 1)) AS touch_index
  WHERE touch_count > 0
)
SELECT
  CAST(campaign_id AS STRING) AS campaign_id,
  CAST(touch_channel AS STRING) AS touch_channel,
  CAST(COUNT(*) AS BIGINT) AS touches,
  CAST(COUNT(DISTINCT customer_id) AS BIGINT) AS customers_reached
FROM touches
GROUP BY campaign_id, touch_channel;
