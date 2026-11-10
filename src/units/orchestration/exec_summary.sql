-- exec_summary: executive summary over the four published gold marts.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.exec_summary') AS
SELECT CAST('as_of_2025-12-31' AS STRING)                    AS snapshot_label,
       DATE'2025-12-31'                                      AS as_of_date,
       CAST(dr.total_revenue AS DECIMAL(38,2))               AS total_revenue,
       CAST(dr.total_orders AS BIGINT)                       AS total_orders,
       CAST(FLOOR(ltv.avg_ltv, 2) AS DECIMAL(38,2))          AS avg_customer_ltv,
       CAST(FLOOR(rr.return_ratio, 15) * 100 AS DECIMAL(38,15)) AS overall_return_pct,
       CAST(FLOOR(sla.avg_hours_to_deliver, 4) AS DECIMAL(38,4)) AS avg_ship_hours
FROM (SELECT SUM(revenue) AS total_revenue, SUM(order_count) AS total_orders
      FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.daily_revenue')) dr
CROSS JOIN (SELECT AVG(ltv) AS avg_ltv
            FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv')) ltv
CROSS JOIN (SELECT CAST(SUM(returned_qty) AS DECIMAL(14,4)) / CAST(SUM(sold_qty) AS DECIMAL(14,4)) AS return_ratio
            FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate')) rr
CROSS JOIN (SELECT SUM(avg_hours_to_deliver * delivered) / SUM(delivered) AS avg_hours_to_deliver
            FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.shipping_sla')) sla
