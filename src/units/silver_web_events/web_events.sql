CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.web_events') AS
SELECT
    CAST(event_id AS BIGINT) AS event_id,
    CAST(customer_id AS BIGINT) AS customer_id,
    CAST(event_ts AS TIMESTAMP_NTZ) AS event_ts,
    CAST(event_type AS STRING) AS event_type,
    CAST(page_url AS STRING) AS page_url
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events')
WHERE _drop = :drop;
