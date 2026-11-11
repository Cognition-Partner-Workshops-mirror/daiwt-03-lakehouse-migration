-- category_mix: revenue share per product category (legacy RATIO_TO_REPORT).
-- The share is an exact decimal quotient of revenue over the grand total,
-- expanded by BIGINT long division to 30 fractional digits and then
-- converted to DOUBLE; NULL when the total is zero.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.category_mix') AS
WITH category_revenue AS (
    SELECT p.category,
           SUM(oi.quantity) AS units_sold,
           SUM(oi.quantity * (oi.unit_price - oi.discount)) AS revenue
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
    JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p ON p.product_id = oi.product_id
    GROUP BY p.category
),
cents AS (
    SELECT category, units_sold, revenue,
           CAST(revenue * 100 AS BIGINT) AS revenue_cents,
           NULLIF(CAST(SUM(revenue) OVER () * 100 AS BIGINT), 0) AS total_cents
    FROM category_revenue
),
step1 AS (
    SELECT *, (revenue_cents * 1000000) DIV total_cents AS q1,
              (revenue_cents * 1000000) % total_cents AS r1
    FROM cents
),
step2 AS (
    SELECT *, (r1 * 1000000) DIV total_cents AS q2,
              (r1 * 1000000) % total_cents AS r2
    FROM step1
),
step3 AS (
    SELECT *, (r2 * 1000000) DIV total_cents AS q3,
              (r2 * 1000000) % total_cents AS r3
    FROM step2
),
step4 AS (
    SELECT *, (r3 * 1000000) DIV total_cents AS q4,
              (r3 * 1000000) % total_cents AS r4
    FROM step3
),
step5 AS (
    SELECT *, (r4 * 1000000) DIV total_cents AS q5
    FROM step4
)
SELECT CAST(category AS STRING) AS category,
       CAST(units_sold AS BIGINT) AS units_sold,
       CAST(revenue AS DECIMAL(38,2)) AS revenue,
       CAST(concat(CAST(q1 DIV 1000000 AS STRING), '.',
                   lpad(CAST(q1 % 1000000 AS STRING), 6, '0'),
                   lpad(CAST(q2 AS STRING), 6, '0'),
                   lpad(CAST(q3 AS STRING), 6, '0'),
                   lpad(CAST(q4 AS STRING), 6, '0'),
                   lpad(CAST(q5 AS STRING), 6, '0')) AS DOUBLE) AS revenue_share
FROM step5;
