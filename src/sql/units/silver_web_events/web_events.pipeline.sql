CREATE TEMPORARY VIEW web_events_candidates AS
SELECT * FROM ${catalog}.${silver_schema}.asof_web_events(:drop)
UNION ALL
SELECT CAST(NULL AS BIGINT), CAST(NULL AS BIGINT),
       CAST('2025-12-31 00:00:00' AS TIMESTAMP_NTZ),
       CAST('page_view' AS STRING), CAST('/synthetic-bad-row' AS STRING)
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW web_events (
  CONSTRAINT valid_key EXPECT (event_id IS NOT NULL) ON VIOLATION DROP ROW
)
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT event_id, customer_id, event_ts, event_type, page_url FROM web_events_candidates;

CREATE OR REFRESH MATERIALIZED VIEW web_events_quarantine
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT *, 'null key' AS reason FROM web_events_candidates WHERE event_id IS NULL;
