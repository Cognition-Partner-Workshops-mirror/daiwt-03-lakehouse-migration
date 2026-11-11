CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate') AS
WITH quantities AS (
    SELECT
        p.category,
        CAST(SUM(oi.quantity) AS BIGINT) AS sold_qty,
        CAST(COALESCE(SUM(r.quantity), 0) AS BIGINT) AS returned_qty
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
    JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
        ON p.product_id = oi.product_id
    LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.returns') r
        ON r.order_item_id = oi.order_item_id
    GROUP BY p.category
), ratios AS (
    SELECT
        category,
        sold_qty,
        returned_qty,
        CAST(returned_qty AS DECIMAL(14,4))
            / CAST(sold_qty AS DECIMAL(14,4)) AS return_ratio
    FROM quantities
)
SELECT
    category,
    sold_qty,
    returned_qty,
    CAST(returned_qty DIV sold_qty AS BIGINT) AS return_rate_int,
    -- Recover the truncated quotient as an integer before fixed-point scaling.
    CAST(
        CAST(ROUND(
            CASE WHEN return_ratio < 0 THEN -FLOOR(ABS(return_ratio), 15)
                ELSE FLOOR(return_ratio, 15)
            END * 1000000000000000
        ) AS DECIMAL(23,0))
        * 0.0000000000001
        AS DECIMAL(38,15)
    ) AS return_pct
FROM ratios
ORDER BY category;
