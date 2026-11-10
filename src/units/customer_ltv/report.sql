CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_customer_ltv') AS
SELECT
    CAST(region AS STRING) AS region,
    CAST(COUNT(*) AS BIGINT) AS customers,
    CAST(SUM(order_count) AS BIGINT) AS orders,
    CAST(SUM(ltv) AS DECIMAL(38, 2)) AS total_ltv,
    CAST(SIGN(AVG(ltv)) * FLOOR(ABS(AVG(ltv)), 2) AS DECIMAL(38, 2)) AS avg_ltv
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv')
GROUP BY region;
