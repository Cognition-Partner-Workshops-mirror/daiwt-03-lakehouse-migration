-- BI report: the exec summary as published.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_orchestration') AS
SELECT snapshot_label, as_of_date, total_revenue, total_orders,
       avg_customer_ltv, overall_return_pct, avg_ship_hours
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.exec_summary')
