CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla') AS
WITH shipment_hours AS (
  SELECT
    carrier,
    delivered_ts,
    -- Count crossed hour boundaries, including intervals before shipment.
    TIMESTAMPDIFF(
      HOUR,
      DATE_TRUNC('HOUR', ship_ts),
      DATE_TRUNC('HOUR', delivered_ts)
    ) AS hours_to_deliver
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.shipments')
), carrier_totals AS (
  SELECT
    carrier,
    COUNT(*) AS shipments,
    COUNT(delivered_ts) AS delivered,
    COUNT(*) - COUNT(delivered_ts) AS in_flight,
    AVG(hours_to_deliver) AS mean_hours,
    MAX(hours_to_deliver) AS max_hours_to_deliver,
    SUM(CASE WHEN hours_to_deliver <= 96 THEN 1 ELSE 0 END) AS on_time_96h,
    MIN(HOUR(CONVERT_TIMEZONE('UTC', 'America/Los_Angeles', delivered_ts)))
      AS earliest_local_delivery_hour
  FROM shipment_hours
  GROUP BY carrier
)
SELECT
  CAST(carrier AS STRING) AS carrier,
  CAST(shipments AS BIGINT) AS shipments,
  CAST(delivered AS BIGINT) AS delivered,
  CAST(in_flight AS BIGINT) AS in_flight,
  -- Integer AVG truncates toward zero before the fixed-point cast.
  CAST(SIGN(mean_hours) * FLOOR(ABS(mean_hours)) AS DECIMAL(10, 2)) AS avg_hours_to_deliver,
  CAST(max_hours_to_deliver AS BIGINT) AS max_hours_to_deliver,
  CAST(on_time_96h AS BIGINT) AS on_time_96h,
  CAST(earliest_local_delivery_hour AS INT) AS earliest_local_delivery_hour
FROM carrier_totals
ORDER BY carrier;
