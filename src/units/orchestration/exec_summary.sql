-- Aggregate the four published marts for the captured reporting snapshot.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.exec_summary') AS
WITH revenue AS (
    SELECT SUM(revenue) AS total_revenue,
           SUM(order_count) AS total_orders
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue')
), customer_value AS (
    SELECT AVG(ltv) AS avg_ltv
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv')
), returns AS (
    SELECT CAST(SUM(returned_qty) AS DECIMAL(14,4))
           / CAST(SUM(sold_qty) AS DECIMAL(14,4)) AS return_quotient
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate')
), shipping AS (
    SELECT SUM(avg_hours_to_deliver * delivered) / SUM(delivered) AS avg_hours
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla')
)
SELECT CAST('as_of_2025-12-31' AS STRING) AS snapshot_label,
       CAST('2025-12-31' AS DATE) AS as_of_date,
       CAST(revenue.total_revenue AS DECIMAL(38,2)) AS total_revenue,
       CAST(revenue.total_orders AS BIGINT) AS total_orders,
       CAST(CASE WHEN customer_value.avg_ltv < 0
                 THEN -FLOOR(-customer_value.avg_ltv, 2)
                 ELSE FLOOR(customer_value.avg_ltv, 2) END
            AS DECIMAL(38,2)) AS avg_customer_ltv,
       -- Fix the quotient's scale before multiplying by the percentage factor.
       CAST(CAST(CASE WHEN returns.return_quotient < 0
                      THEN -FLOOR(-returns.return_quotient, 15)
                      ELSE FLOOR(returns.return_quotient, 15) END
                 AS DECIMAL(30,15)) * CAST(100 AS DECIMAL(3,0))
            AS DECIMAL(38,15)) AS overall_return_pct,
       CAST(CASE WHEN shipping.avg_hours < 0
                 THEN -FLOOR(-shipping.avg_hours, 4)
                 ELSE FLOOR(shipping.avg_hours, 4) END
            AS DECIMAL(38,4)) AS avg_ship_hours
FROM revenue
CROSS JOIN customer_value
CROSS JOIN returns
CROSS JOIN shipping;
