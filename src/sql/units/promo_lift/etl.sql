CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.promo_lift')
USING DELTA
AS
WITH order_totals AS (
    SELECT o.order_id,
           o.sales_channel,
           SUM(oi.quantity * (oi.unit_price - oi.discount)) AS order_total
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
    JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
           ON oi.order_id = o.order_id
    GROUP  BY o.order_id, o.sales_channel
),
ranked AS (
    SELECT sales_channel,
           order_total,
           ROW_NUMBER() OVER (PARTITION BY sales_channel ORDER BY order_total ASC NULLS LAST) AS rn,
           COUNT(order_total) OVER (PARTITION BY sales_channel)                              AS n
    FROM   order_totals
),
positions AS (
    SELECT sales_channel,
           order_total,
           rn,
           CAST(0.5 * (n - 1) AS DECIMAL(38,6)) AS pos_50,
           CAST(0.9 * (n - 1) AS DECIMAL(38,6)) AS pos_90
    FROM   ranked
),
endpoints AS (
    SELECT sales_channel,
           CAST(COUNT(*) AS BIGINT)                                            AS order_count,
           MAX(pos_50)                                                         AS pos_50,
           MAX(pos_90)                                                         AS pos_90,
           MAX(CASE WHEN rn = 1 + FLOOR(pos_50) THEN order_total END)          AS lo_50,
           MAX(CASE WHEN rn = 2 + FLOOR(pos_50) THEN order_total END)          AS hi_50,
           MAX(CASE WHEN rn = 1 + FLOOR(pos_90) THEN order_total END)          AS lo_90,
           MAX(CASE WHEN rn = 2 + FLOOR(pos_90) THEN order_total END)          AS hi_90
    FROM   positions
    GROUP  BY sales_channel
)
SELECT sales_channel,
       order_count,
       CAST(FLOOR(lo_50 + (pos_50 - FLOOR(pos_50)) * (COALESCE(hi_50, lo_50) - lo_50), 2) AS DECIMAL(38,2)) AS median_order_value,
       CAST(FLOOR(lo_90 + (pos_90 - FLOOR(pos_90)) * (COALESCE(hi_90, lo_90) - lo_90), 2) AS DECIMAL(38,2)) AS p90_order_value
FROM   endpoints;
