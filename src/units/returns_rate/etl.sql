CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate') AS
SELECT CAST(p.category AS STRING)                                       AS category,
       CAST(SUM(oi.quantity) AS BIGINT)                                 AS sold_qty,
       CAST(COALESCE(SUM(r.quantity), 0) AS BIGINT)                     AS returned_qty,
       CAST(COALESCE(SUM(r.quantity), 0) DIV SUM(oi.quantity) AS BIGINT) AS return_rate_int,
       CAST(CAST(ROUND(FLOOR(CAST(COALESCE(SUM(r.quantity), 0) AS DECIMAL(14,4))
                             / CAST(SUM(oi.quantity) AS DECIMAL(14,4)), 15)
                       * 1000000000000000) AS DECIMAL(20,0))
            * 100 * 0.000000000000001 AS DECIMAL(38,15))               AS return_pct
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
       ON p.product_id = oi.product_id
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.returns') r
       ON r.order_item_id = oi.order_item_id
GROUP  BY p.category;
