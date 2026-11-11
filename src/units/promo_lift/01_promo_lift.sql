CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.promo_lift') AS
WITH order_totals AS (
  SELECT
    o.order_id,
    o.sales_channel,
    CAST(SUM(oi.quantity * (oi.unit_price - oi.discount)) AS DECIMAL(38,2)) AS order_total
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
  JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
    ON oi.order_id = o.order_id
  GROUP BY o.order_id, o.sales_channel
), ranked AS (
  SELECT
    sales_channel,
    order_total,
    ROW_NUMBER() OVER (PARTITION BY sales_channel ORDER BY order_total NULLS LAST) AS value_rank,
    COUNT(order_total) OVER (PARTITION BY sales_channel) AS value_count
  FROM order_totals
), endpoints AS (
  SELECT
    sales_channel,
    COUNT(*) AS order_count,
    MAX(value_count) AS value_count,
    MAX(CASE WHEN value_rank = (value_count - 1) DIV 2 + 1 THEN order_total END) AS median_low,
    MAX(CASE WHEN value_rank = value_count DIV 2 + 1 THEN order_total END) AS median_high,
    MAX(CASE WHEN value_rank = ((value_count - 1) * 9) DIV 10 + 1 THEN order_total END) AS p90_low,
    MAX(CASE WHEN value_rank = ((value_count - 1) * 9 + 9) DIV 10 + 1 THEN order_total END) AS p90_high
  FROM ranked
  GROUP BY sales_channel
)
SELECT
  CAST(sales_channel AS STRING) AS sales_channel,
  CAST(order_count AS BIGINT) AS order_count,
  CAST(FLOOR(
    CAST(median_low AS DECIMAL(28,2))
      + (CAST(median_high AS DECIMAL(28,2)) - CAST(median_low AS DECIMAL(28,2))) * CAST(0.5 AS DECIMAL(2,1)),
    2
  ) AS DECIMAL(38,2)) AS median_order_value,
  CAST(FLOOR(
    CAST(p90_low AS DECIMAL(28,2))
      + (CAST(p90_high AS DECIMAL(28,2)) - CAST(p90_low AS DECIMAL(28,2)))
        * CAST(MOD((value_count - 1) * 9, 10) AS DECIMAL(2,0)) * CAST(0.1 AS DECIMAL(2,1)),
    2
  ) AS DECIMAL(38,2)) AS p90_order_value
FROM endpoints;
