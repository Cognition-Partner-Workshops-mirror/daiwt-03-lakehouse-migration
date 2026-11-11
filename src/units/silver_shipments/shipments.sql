CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.shipments') AS
SELECT
  CAST(shipment_id AS BIGINT) AS shipment_id,
  CAST(order_id AS BIGINT) AS order_id,
  CAST(carrier AS STRING) AS carrier,
  CAST(ship_ts AS TIMESTAMP_NTZ) AS ship_ts,
  CAST(delivered_ts AS TIMESTAMP_NTZ) AS delivered_ts
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments')
WHERE _drop = :drop;
