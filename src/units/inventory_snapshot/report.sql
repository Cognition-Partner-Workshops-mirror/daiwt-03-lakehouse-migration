-- BI report: lowest stock products as of the snapshot.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_inventory_snapshot') AS
SELECT product_id, snapshot_date, units_sold, on_hand
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.inventory_snapshot')
ORDER BY on_hand ASC, product_id
LIMIT 50;
