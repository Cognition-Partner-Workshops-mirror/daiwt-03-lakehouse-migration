CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_sessionization') AS
SELECT
  CAST(customer_id AS BIGINT) AS customer_id,
  CAST(COUNT(*) AS BIGINT) AS sessions,
  CAST(SUM(event_count) AS BIGINT) AS events,
  CAST(SUM(checkout_events) AS BIGINT) AS checkout_sessions
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.web_sessions')
GROUP BY customer_id;
