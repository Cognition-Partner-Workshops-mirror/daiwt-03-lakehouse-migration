CREATE TEMPORARY VIEW campaign_touches_candidates AS
SELECT touch_id, customer_id, payload
FROM ${catalog}.${silver_schema}.asof_campaign_touches(:drop)
UNION ALL
SELECT CAST(NULL AS BIGINT) AS touch_id, CAST(900000001 AS BIGINT) AS customer_id,
       CAST('{"customer_ref":900000001,"touches":[],"meta":{"source":"synthetic","batch":0}}' AS STRING) AS payload
WHERE '${silver_bad_rows}' = 'true'
UNION ALL
SELECT CAST(NULL AS BIGINT) AS touch_id, CAST(NULL AS BIGINT) AS customer_id,
       CAST(NULL AS STRING) AS payload
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW campaign_touches (
  CONSTRAINT valid_touch_id EXPECT (touch_id IS NOT NULL) ON VIOLATION DROP ROW
)
AS SELECT touch_id, customer_id, payload FROM campaign_touches_candidates;

CREATE OR REFRESH MATERIALIZED VIEW campaign_touches_quarantine AS
SELECT *, 'null touch_id' AS reason FROM campaign_touches_candidates WHERE touch_id IS NULL;
