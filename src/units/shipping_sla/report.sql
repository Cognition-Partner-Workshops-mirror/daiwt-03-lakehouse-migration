CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_shipping_sla') AS
SELECT carrier, shipments, delivered, in_flight,
       avg_hours_to_deliver, max_hours_to_deliver, on_time_96h
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla')
ORDER BY carrier;
