CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_basket_affinity') AS
SELECT
  CAST(b.product_id_a AS INT) AS product_id_a,
  CAST(b.product_id_b AS INT) AS product_id_b,
  CAST(pa.product_name || ' + ' || pb.product_name AS STRING) AS pair,
  CAST(b.pair_orders AS BIGINT) AS pair_orders
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.basket_affinity') b
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.products') pa
  ON pa.product_id = b.product_id_a
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.products') pb
  ON pb.product_id = b.product_id_b
ORDER BY b.pair_orders DESC, b.product_id_a ASC, b.product_id_b ASC
LIMIT 50;
