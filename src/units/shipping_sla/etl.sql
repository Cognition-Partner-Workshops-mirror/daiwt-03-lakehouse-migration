CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla') AS
WITH shipment_hours AS (
  SELECT carrier,
         delivered_ts,
         CAST(datediff(CAST(delivered_ts AS DATE), CAST(ship_ts AS DATE)) AS BIGINT) * 24
           + hour(delivered_ts) - hour(ship_ts) AS delivery_hours
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.shipments')
)
SELECT CAST(carrier AS STRING) AS carrier,
       CAST(COUNT(*) AS BIGINT) AS shipments,
       CAST(COUNT(delivered_ts) AS BIGINT) AS delivered,
       CAST(COUNT(*) - COUNT(delivered_ts) AS BIGINT) AS in_flight,
       CAST(CAST(AVG(delivery_hours) AS BIGINT) AS DECIMAL(10,2)) AS avg_hours_to_deliver,
       CAST(MAX(delivery_hours) AS BIGINT) AS max_hours_to_deliver,
       CAST(SUM(CASE WHEN delivery_hours <= 96 THEN 1 ELSE 0 END) AS BIGINT) AS on_time_96h,
       CAST(MIN(hour(from_utc_timestamp(delivered_ts, 'America/Los_Angeles'))) AS INT)
         AS earliest_local_delivery_hour
FROM shipment_hours
GROUP BY carrier;
