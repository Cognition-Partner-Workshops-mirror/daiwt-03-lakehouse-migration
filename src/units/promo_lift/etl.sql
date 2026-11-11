CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.promo_lift') AS
WITH order_totals AS (
    SELECT o.order_id,
           o.sales_channel,
           CAST(SUM(oi.quantity * (CAST(oi.unit_price AS DECIMAL(18,2))
                                - CAST(oi.discount AS DECIMAL(18,2)))) AS DECIMAL(28,2)) AS order_total
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
    JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
      ON oi.order_id = o.order_id
    GROUP BY o.order_id, o.sales_channel
), ranked AS (
    SELECT sales_channel,
           CAST(order_total * 100 AS DECIMAL(28,0)) AS cents,
           ROW_NUMBER() OVER (PARTITION BY sales_channel ORDER BY order_total NULLS LAST) AS position,
           COUNT(order_total) OVER (PARTITION BY sales_channel) AS value_count
    FROM order_totals
), endpoints AS (
    SELECT sales_channel,
           COUNT(*) AS order_count,
           MAX(MOD(value_count - 1, 2)) AS median_weight,
           MAX(MOD(9 * (value_count - 1), 10)) AS p90_weight,
           MAX(CASE WHEN position = (value_count - 1) DIV 2 + 1 THEN cents END) AS median_low,
           MAX(CASE WHEN position = (value_count - 1) DIV 2 + 1 + MOD(value_count - 1, 2) THEN cents END) AS median_high,
           MAX(CASE WHEN position = (9 * (value_count - 1)) DIV 10 + 1 THEN cents END) AS p90_low,
           MAX(CASE WHEN position = (9 * (value_count - 1)) DIV 10 + 1
                                    + CASE WHEN MOD(9 * (value_count - 1), 10) > 0 THEN 1 ELSE 0 END
                    THEN cents END) AS p90_high
    FROM ranked
    GROUP BY sales_channel
), interpolated AS (
    SELECT sales_channel, order_count,
           (median_low * (2 - median_weight) + median_high * median_weight) * CAST(0.5 AS DECIMAL(2,1)) AS median_cents,
           (p90_low * (10 - p90_weight) + p90_high * p90_weight) * CAST(0.1 AS DECIMAL(2,1)) AS p90_cents
    FROM endpoints
)
SELECT CAST(sales_channel AS STRING) AS sales_channel,
       CAST(order_count AS BIGINT) AS order_count,
       CAST(SIGN(median_cents) * FLOOR(ABS(median_cents)) * CAST(0.01 AS DECIMAL(3,2)) AS DECIMAL(28,2)) AS median_order_value,
       CAST(SIGN(p90_cents) * FLOOR(ABS(p90_cents)) * CAST(0.01 AS DECIMAL(3,2)) AS DECIMAL(28,2)) AS p90_order_value
FROM interpolated;
