CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.web_sessions')
USING DELTA
AS
WITH flagged AS (
    SELECT customer_id,
           event_id,
           event_ts,
           event_type,
           CASE
             WHEN LAG(event_ts) OVER (PARTITION BY customer_id ORDER BY event_ts, event_id) IS NULL THEN 1
             WHEN TIMESTAMPDIFF(SECOND,
                                DATE_TRUNC('SECOND', LAG(event_ts) OVER (PARTITION BY customer_id ORDER BY event_ts, event_id)),
                                DATE_TRUNC('SECOND', event_ts)) > 1800 THEN 1
             ELSE 0
           END AS new_session
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.web_events')
    WHERE  customer_id IS NOT NULL
),
numbered AS (
    SELECT customer_id,
           event_id,
           event_ts,
           event_type,
           SUM(new_session) OVER (PARTITION BY customer_id
                                  ORDER BY event_ts, event_id
                                  ROWS UNBOUNDED PRECEDING) AS session_id
    FROM   flagged
)
SELECT CAST(customer_id AS BIGINT)                                             AS customer_id,
       CAST(session_id AS BIGINT)                                              AS session_id,
       CAST(MIN(event_ts) AS TIMESTAMP_NTZ)                                    AS session_start_ts,
       CAST(MAX(event_ts) AS TIMESTAMP_NTZ)                                    AS session_end_ts,
       CAST(COUNT(*) AS BIGINT)                                                AS event_count,
       CAST(SUM(CASE WHEN event_type = 'checkout' THEN 1 ELSE 0 END) AS BIGINT) AS checkout_events
FROM   numbered
GROUP  BY customer_id, session_id;
