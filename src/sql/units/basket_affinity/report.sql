CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_basket_affinity')
USING DELTA
AS
SELECT b.product_id_a,
       b.product_id_b,
       pa.product_name || ' + ' || pb.product_name AS pair,
       b.pair_orders
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.basket_affinity') b
JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.products') pa ON pa.product_id = b.product_id_a
JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.products') pb ON pb.product_id = b.product_id_b
ORDER  BY b.pair_orders DESC, b.product_id_a, b.product_id_b
LIMIT  50;
