CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.exec_summary')
USING DELTA AS
SELECT CAST('as_of_2025-12-31' AS VARCHAR(32)) AS snapshot_label,
       DATE '2025-12-31' AS as_of_date,
       CAST(dr.total_revenue AS DECIMAL(38,2)) AS total_revenue,
       dr.total_orders,
       CAST(CASE WHEN ltv.avg_ltv < 0 THEN -FLOOR(-ltv.avg_ltv, 2) ELSE FLOOR(ltv.avg_ltv, 2) END AS DECIMAL(38,2)) AS avg_customer_ltv,
       CAST(CAST(FLOOR(rr.return_ratio, 15) AS DECIMAL(29,15))
            * CAST(100 AS DECIMAL(3,0)) AS DECIMAL(38,15)) AS overall_return_pct,
       CAST(CASE WHEN sla.avg_hours_to_deliver < 0 THEN -FLOOR(-sla.avg_hours_to_deliver, 4) ELSE FLOOR(sla.avg_hours_to_deliver, 4) END AS DECIMAL(38,4)) AS avg_ship_hours
FROM (
    SELECT SUM(revenue) AS total_revenue, SUM(order_count) AS total_orders
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue')
) dr
CROSS JOIN (
    SELECT AVG(ltv) AS avg_ltv
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv')
) ltv
CROSS JOIN (
    SELECT CAST(SUM(returned_qty) AS DECIMAL(14,4))
           / CAST(SUM(sold_qty) AS DECIMAL(14,4)) AS return_ratio
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate')
) rr
CROSS JOIN (
    SELECT SUM(avg_hours_to_deliver * delivered) / SUM(delivered) AS avg_hours_to_deliver
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla')
) sla;
