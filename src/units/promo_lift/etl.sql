CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.promo_lift') AS
WITH order_totals AS (
    SELECT o.order_id,
           o.sales_channel,
           SUM(oi.quantity * (oi.unit_price - oi.discount)) AS order_total
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
    JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
      ON oi.order_id = o.order_id
    GROUP BY o.order_id, o.sales_channel
), ranked AS (
    SELECT sales_channel,
           order_total,
           ROW_NUMBER() OVER (PARTITION BY sales_channel ORDER BY order_total NULLS LAST) AS rn,
           COUNT(order_total) OVER (PARTITION BY sales_channel) AS n,
           COUNT(*) OVER (PARTITION BY sales_channel) AS order_count
    FROM order_totals
), percentiles AS (
    SELECT CAST(0.5 AS DECIMAL(2,1)) AS p
    UNION ALL
    SELECT CAST(0.9 AS DECIMAL(2,1)) AS p
), positions AS (
    SELECT ranked.*, p,
           CAST(1 AS DECIMAL(12,0)) + p * CAST(n - 1 AS DECIMAL(12,0)) AS pos
    FROM ranked CROSS JOIN percentiles
), endpoints AS (
    SELECT sales_channel, p, pos, MAX(order_count) AS order_count,
           CAST(MAX(CASE WHEN rn = FLOOR(pos) THEN order_total END) AS DECIMAL(32,2)) AS lo,
           CAST(MAX(CASE WHEN rn = CEIL(pos) THEN order_total END) AS DECIMAL(32,2)) AS hi
    FROM positions
    GROUP BY sales_channel, p, pos
), interpolated AS (
    SELECT sales_channel, p, order_count,
           CAST(FLOOR(
               CAST(1 - (pos - FLOOR(pos)) AS DECIMAL(2,1)) * lo
               + CAST(pos - FLOOR(pos) AS DECIMAL(2,1)) * hi,
               2
           ) AS DECIMAL(38,2)) AS order_value
    FROM endpoints
)
SELECT CAST(sales_channel AS STRING) AS sales_channel,
       CAST(MAX(order_count) AS BIGINT) AS order_count,
       CAST(MAX(CASE WHEN p = 0.5 THEN order_value END) AS DECIMAL(38,2)) AS median_order_value,
       CAST(MAX(CASE WHEN p = 0.9 THEN order_value END) AS DECIMAL(38,2)) AS p90_order_value
FROM interpolated
GROUP BY sales_channel;
