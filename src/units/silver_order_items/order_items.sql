CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') AS
SELECT
  CAST(order_item_id AS BIGINT) AS order_item_id,
  CAST(order_id AS BIGINT) AS order_id,
  CAST(product_id AS INT) AS product_id,
  CAST(quantity AS INT) AS quantity,
  CAST(unit_price AS DECIMAL(12,2)) AS unit_price,
  CAST(discount AS DECIMAL(12,2)) AS discount
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items')
WHERE _drop = :drop;
