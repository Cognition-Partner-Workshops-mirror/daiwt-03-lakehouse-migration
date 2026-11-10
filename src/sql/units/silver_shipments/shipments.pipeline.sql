CREATE TEMPORARY VIEW shipments_candidates AS
SELECT * FROM ${catalog}.${silver_schema}.asof_shipments(:drop)
UNION ALL
SELECT CAST(NULL AS BIGINT), CAST(-1 AS BIGINT), CAST('dev-only' AS STRING),
       CAST('2025-12-31 12:00:00' AS TIMESTAMP_NTZ), CAST(NULL AS TIMESTAMP_NTZ)
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW shipments (
  CONSTRAINT valid_key EXPECT (shipment_id IS NOT NULL) ON VIOLATION DROP ROW
)
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT shipment_id, order_id, carrier, ship_ts, delivered_ts FROM shipments_candidates;

CREATE OR REFRESH MATERIALIZED VIEW shipments_quarantine
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS
SELECT *, 'null key' AS reason FROM shipments_candidates
WHERE NOT COALESCE(shipment_id IS NOT NULL, false);
