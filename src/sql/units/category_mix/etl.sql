CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.category_mix')
USING DELTA
AS
SELECT category,
       units_sold,
       revenue,
       CAST(try_divide(CAST(revenue AS DECIMAL(18,2)),
                       CAST(SUM(revenue) OVER () AS DECIMAL(18,2))) AS DOUBLE) AS revenue_share
FROM (
    SELECT p.category,
           CAST(SUM(oi.quantity) AS BIGINT)                                         AS units_sold,
           CAST(SUM(oi.quantity * (oi.unit_price - oi.discount)) AS DECIMAL(38,2))  AS revenue
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
    JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
           ON p.product_id = oi.product_id
    GROUP  BY p.category
) x;
