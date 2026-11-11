CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.category_mix') AS
WITH category_totals AS (
  SELECT
    p.category,
    CAST(SUM(oi.quantity) AS BIGINT) AS units_sold,
    CAST(SUM(oi.quantity * (oi.unit_price - oi.discount)) AS DECIMAL(38,2)) AS revenue
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
  JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
    ON p.product_id = oi.product_id
  GROUP BY p.category
), scaled AS (
  SELECT
    category,
    units_sold,
    revenue,
    CASE WHEN SIGN(revenue) * SIGN(SUM(revenue) OVER ()) < 0 THEN '-' ELSE '' END AS sign,
    ABS(CAST(revenue * 100 AS BIGINT)) AS numerator,
    NULLIF(ABS(CAST(SUM(revenue) OVER () * 100 AS BIGINT)), 0) AS denominator
  FROM category_totals
), d0 AS (
  SELECT *, numerator DIV denominator AS q0, numerator % denominator AS r0
  FROM scaled
), d1 AS (
  SELECT *, (r0 * 1000000) DIV denominator AS q1, (r0 * 1000000) % denominator AS r1
  FROM d0
), d2 AS (
  SELECT *, (r1 * 1000000) DIV denominator AS q2, (r1 * 1000000) % denominator AS r2
  FROM d1
), d3 AS (
  SELECT *, (r2 * 1000000) DIV denominator AS q3, (r2 * 1000000) % denominator AS r3
  FROM d2
), d4 AS (
  SELECT *, (r3 * 1000000) DIV denominator AS q4, (r3 * 1000000) % denominator AS r4
  FROM d3
), d5 AS (
  SELECT *, (r4 * 1000000) DIV denominator AS q5, (r4 * 1000000) % denominator AS r5
  FROM d4
), d6 AS (
  SELECT *, (r5 * 1000000) DIV denominator AS q6, (r5 * 1000000) % denominator AS r6
  FROM d5
)
SELECT
  CAST(category AS STRING) AS category,
  units_sold,
  revenue,
  CAST(
    CONCAT(
      sign,
      CAST(q0 AS STRING),
      '.',
      LPAD(CAST(q1 AS STRING), 6, '0'),
      LPAD(CAST(q2 AS STRING), 6, '0'),
      LPAD(CAST(q3 AS STRING), 6, '0'),
      LPAD(CAST(q4 AS STRING), 6, '0'),
      LPAD(CAST(q5 AS STRING), 6, '0'),
      LPAD(CAST(q6 AS STRING), 6, '0')
    ) AS DOUBLE
  ) AS revenue_share
FROM d6;
