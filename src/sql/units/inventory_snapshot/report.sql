-- gold.report_inventory_snapshot: low stock as of the snapshot
-- (port of legacy/redshift/units/inventory_snapshot/report.sql).
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_inventory_snapshot')
USING DELTA
AS
SELECT product_id, snapshot_date, units_sold, on_hand
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.inventory_snapshot')
ORDER  BY on_hand ASC NULLS LAST, product_id ASC NULLS LAST
LIMIT  50;
