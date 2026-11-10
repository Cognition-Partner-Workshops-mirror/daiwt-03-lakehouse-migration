-- gold.inventory_snapshot: per-product units sold and clamped on-hand stock
-- as of the fixed snapshot date (port of legacy/redshift/units/inventory_snapshot/etl.sql).
-- The legacy procedure stages per-product sums, then rebuilds the freshly
-- created table from all products, so a full replacement is equivalent.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.inventory_snapshot')
USING DELTA
AS
WITH stg_inventory AS (
    SELECT product_id,
           CAST(SUM(quantity) AS BIGINT) AS units_sold
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items')
    GROUP  BY product_id
)
SELECT CAST(p.product_id AS INT)                                         AS product_id,
       DATE'2025-12-31'                                                  AS snapshot_date,
       COALESCE(s.units_sold, CAST(0 AS BIGINT))                         AS units_sold,
       CAST(GREATEST(500 - COALESCE(s.units_sold, 0), 0) AS INT)         AS on_hand
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
LEFT JOIN stg_inventory s ON s.product_id = p.product_id;
