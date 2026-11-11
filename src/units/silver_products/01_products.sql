CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.products') AS
SELECT
    CAST(product_id AS INT) AS product_id,
    CAST(sku AS STRING) AS sku,
    CAST(product_name AS STRING) AS product_name,
    CAST(category AS STRING) AS category,
    CAST(subcategory AS STRING) AS subcategory,
    CAST(unit_price AS DECIMAL(12,2)) AS unit_price,
    CAST(cost AS DECIMAL(12,2)) AS cost,
    CAST(active AS BOOLEAN) AS active
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.products')
WHERE _drop = :drop;
