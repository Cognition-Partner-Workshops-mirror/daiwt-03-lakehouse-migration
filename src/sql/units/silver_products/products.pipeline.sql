CREATE TEMPORARY VIEW products_candidates AS
SELECT * FROM ${catalog}.${silver_schema}.asof_products(:drop)
UNION ALL
SELECT
  CAST(NULL AS INT) AS product_id,
  CAST('SKU-BAD-0001' AS STRING) AS sku,
  CAST('Synthetic bad product' AS STRING) AS product_name,
  CAST('Synthetic' AS STRING) AS category,
  CAST('synthetic-sub-1' AS STRING) AS subcategory,
  CAST(1.00 AS DECIMAL(12,2)) AS unit_price,
  CAST(0.50 AS DECIMAL(12,2)) AS cost,
  CAST(true AS BOOLEAN) AS active
WHERE '${silver_bad_rows}' = 'true'
UNION ALL
SELECT
  CAST(NULL AS INT) AS product_id,
  CAST('SKU-BAD-0002' AS STRING) AS sku,
  CAST('Synthetic inactive bad product' AS STRING) AS product_name,
  CAST('Synthetic' AS STRING) AS category,
  CAST('synthetic-sub-2' AS STRING) AS subcategory,
  CAST(2.00 AS DECIMAL(12,2)) AS unit_price,
  CAST(1.00 AS DECIMAL(12,2)) AS cost,
  CAST(false AS BOOLEAN) AS active
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW products (
  CONSTRAINT valid_product_id EXPECT (product_id IS NOT NULL) ON VIOLATION DROP ROW
)
AS SELECT product_id, sku, product_name, category, subcategory, unit_price, cost, active
FROM products_candidates;

CREATE OR REFRESH MATERIALIZED VIEW products_quarantine AS
SELECT *, 'null product_id' AS reason
FROM products_candidates
WHERE product_id IS NULL;
