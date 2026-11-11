CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla') AS
WITH s AS (
  SELECT
    carrier,
    delivered_ts,
    timestampdiff(HOUR, date_trunc('HOUR', ship_ts), date_trunc('HOUR', delivered_ts)) AS hours_to_deliver
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.shipments')
)
SELECT
  CAST(carrier AS STRING) AS carrier,
  CAST(COUNT(*) AS BIGINT) AS shipments,
  CAST(COUNT(delivered_ts) AS BIGINT) AS delivered,
  CAST(COUNT(*) - COUNT(delivered_ts) AS BIGINT) AS in_flight,
  CAST(SUM(hours_to_deliver) DIV NULLIF(COUNT(hours_to_deliver), 0) AS DECIMAL(10, 2)) AS avg_hours_to_deliver,
  CAST(MAX(hours_to_deliver) AS BIGINT) AS max_hours_to_deliver,
  CAST(SUM(CASE WHEN hours_to_deliver <= 96 THEN 1 ELSE 0 END) AS BIGINT) AS on_time_96h,
  CAST(MIN(EXTRACT(HOUR FROM convert_timezone('UTC', 'America/Los_Angeles', delivered_ts))) AS INT) AS earliest_local_delivery_hour
FROM s
GROUP BY carrier;
