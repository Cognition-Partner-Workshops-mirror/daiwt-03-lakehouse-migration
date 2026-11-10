CREATE TEMPORARY VIEW returns_candidates AS
SELECT return_id, order_item_id, quantity, reason, returned_ts
FROM ${catalog}.${silver_schema}.asof_returns(:drop)
UNION ALL
SELECT * FROM VALUES
  (CAST(NULL AS BIGINT), CAST(900000001 AS BIGINT), CAST(1 AS INT), CAST('synthetic null key' AS STRING), CAST('2025-12-31 00:00:00' AS TIMESTAMP_NTZ)),
  (CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS INT), CAST(NULL AS STRING), CAST(NULL AS TIMESTAMP_NTZ))
  AS bad(return_id, order_item_id, quantity, reason, returned_ts)
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW returns (
  CONSTRAINT valid_return_id EXPECT (return_id IS NOT NULL) ON VIOLATION DROP ROW
)
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT return_id, order_item_id, quantity, reason, returned_ts
FROM returns_candidates;

CREATE OR REFRESH MATERIALIZED VIEW returns_quarantine
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT return_id, order_item_id, quantity, reason, returned_ts, 'null return_id' AS reason_rejected
FROM returns_candidates
WHERE return_id IS NULL;
