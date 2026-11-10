CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.finance_monthly')
USING DELTA
AS
SELECT CAST(DATE_TRUNC('MONTH', o.order_ts) AS DATE)                           AS month,
       CAST(CASE WHEN month(o.order_ts) >= 2
                 THEN year(o.order_ts)
                 ELSE year(o.order_ts) - 1
            END AS INT)                                                          AS fiscal_year,
       IDENTIFIER(:catalog || '.' || :silver_schema || '.f_fiscal_qtr')(CAST(o.order_ts AS DATE)) AS fiscal_qtr,
       CAST(COUNT(DISTINCT o.order_id) AS BIGINT)                                AS order_count,
       CAST(SUM(oi.quantity * (oi.unit_price - oi.discount)) AS DECIMAL(38,2))  AS revenue
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
       ON oi.order_id = o.order_id
GROUP  BY 1, 2, 3;
