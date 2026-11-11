CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.store_weekly') AS
SELECT CAST(o.store_id AS INT)                                            AS store_id,
       CAST(DATE_TRUNC('WEEK', o.order_ts) AS DATE)                       AS week_start,
       DATE_ADD(CAST(DATE_TRUNC('WEEK', o.order_ts) AS DATE), 6)          AS week_end,
       CAST(DATEDIFF(CAST(DATE_TRUNC('WEEK', o.order_ts) AS DATE), DATE '2024-12-30') DIV 7 AS BIGINT) AS week_number,
       CAST(COUNT(DISTINCT o.order_id) AS BIGINT)                         AS order_count,
       SUM(oi.quantity * (oi.unit_price - oi.discount))                   AS revenue
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi ON oi.order_id = o.order_id
GROUP  BY o.store_id, DATE_TRUNC('WEEK', o.order_ts);
