CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_inventory_snapshot') AS
SELECT
  CAST(product_id AS INT) AS product_id,
  CAST(snapshot_date AS DATE) AS snapshot_date,
  CAST(units_sold AS BIGINT) AS units_sold,
  CAST(on_hand AS INT) AS on_hand
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.inventory_snapshot')
ORDER BY on_hand ASC, product_id
LIMIT 50;
