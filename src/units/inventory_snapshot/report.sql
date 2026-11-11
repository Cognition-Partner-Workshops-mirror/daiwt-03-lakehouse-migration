CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.inventory_snapshot_report') AS
SELECT product_id, snapshot_date, units_sold, on_hand
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.inventory_snapshot')
ORDER BY on_hand ASC, product_id ASC
LIMIT 50;
