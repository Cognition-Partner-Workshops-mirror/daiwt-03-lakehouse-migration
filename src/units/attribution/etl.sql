CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.attribution') AS
WITH touch_paths AS (
    SELECT
        t.customer_id,
        t.payload,
        CONCAT('$.touches[', CAST(touch_index AS STRING), ']') AS touch_path
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.campaign_touches') AS t
    LATERAL VIEW EXPLODE(
        CASE
            WHEN JSON_ARRAY_LENGTH(GET_JSON_OBJECT(t.payload, '$.touches')) > 0
            THEN SEQUENCE(
                0,
                CAST(JSON_ARRAY_LENGTH(GET_JSON_OBJECT(t.payload, '$.touches')) AS INT) - 1
            )
            ELSE CAST(ARRAY() AS ARRAY<INT>)
        END
    ) touch_indices AS touch_index
), touches AS (
    SELECT
        customer_id,
        GET_JSON_OBJECT(payload, touch_path) AS touch
    FROM touch_paths
)
SELECT
    CAST(GET_JSON_OBJECT(touch, '$.campaign_id') AS STRING) AS campaign_id,
    CAST(GET_JSON_OBJECT(touch, '$.channel') AS STRING) AS touch_channel,
    CAST(COUNT(*) AS BIGINT) AS touches,
    CAST(COUNT(DISTINCT customer_id) AS BIGINT) AS customers_reached
FROM touches
GROUP BY
    CAST(GET_JSON_OBJECT(touch, '$.campaign_id') AS STRING),
    CAST(GET_JSON_OBJECT(touch, '$.channel') AS STRING);
