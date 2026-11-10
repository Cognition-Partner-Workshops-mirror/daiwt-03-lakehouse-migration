CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.basket_affinity') AS
SELECT CAST(a.product_id AS INT) AS product_id_a,
       CAST(b.product_id AS INT) AS product_id_b,
       CAST(COUNT(DISTINCT a.order_id) AS BIGINT) AS pair_orders
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') a
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') b
  ON b.order_id = a.order_id AND b.product_id > a.product_id
GROUP BY a.product_id, b.product_id
HAVING COUNT(DISTINCT a.order_id) >= 5
ORDER BY product_id_a, product_id_b;
