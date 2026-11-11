CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.exec_summary') AS
WITH revenue AS (
    SELECT SUM(revenue) AS total_revenue, SUM(order_count) AS total_orders
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue')
), ltv AS (
    SELECT CAST(SUM(ltv) * CAST(100 AS DECIMAL(3,0)) AS DECIMAL(38,0)) AS cents,
           COUNT(ltv) AS customers
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv')
), returns AS (
    SELECT CAST(SUM(returned_qty) AS DECIMAL(38,0)) *
               CAST(1000000000000000 AS DECIMAL(16,0)) AS scaled_qty,
           CAST(SUM(sold_qty) AS DECIMAL(14,0)) AS sold_qty
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate')
), shipping AS (
    SELECT CAST(SUM(avg_hours_to_deliver * delivered) *
                CAST(10000 AS DECIMAL(5,0)) AS DECIMAL(38,0)) AS scaled_hours,
           SUM(delivered) AS delivered
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla')
)
SELECT CAST('as_of_2025-12-31' AS STRING) AS snapshot_label,
       CAST(DATE '2025-12-31' AS DATE) AS as_of_date,
       CAST(revenue.total_revenue AS DECIMAL(38,2)) AS total_revenue,
       CAST(revenue.total_orders AS BIGINT) AS total_orders,
       -- Remove each remainder before division to truncate without rounding.
       -- The resulting integer quotients are exact in both SQL engines.
       CAST(CAST((ltv.cents - ltv.cents % ltv.customers) / ltv.customers AS DECIMAL(18,0)) *
            CAST(0.01 AS DECIMAL(3,2)) AS DECIMAL(38,2)) AS avg_customer_ltv,
       -- The quotient has scale 15; the scale-13 factor also applies * 100.
       CAST(CAST((returns.scaled_qty - returns.scaled_qty % returns.sold_qty) /
                  returns.sold_qty AS DECIMAL(18,0)) *
            CAST(0.0000000000001 AS DECIMAL(14,13)) AS DECIMAL(38,15)) AS overall_return_pct,
       CAST(CAST((shipping.scaled_hours - shipping.scaled_hours % shipping.delivered) /
                  shipping.delivered AS DECIMAL(18,0)) *
            CAST(0.0001 AS DECIMAL(5,4)) AS DECIMAL(38,4)) AS avg_ship_hours
FROM revenue
CROSS JOIN ltv
CROSS JOIN returns
CROSS JOIN shipping;
