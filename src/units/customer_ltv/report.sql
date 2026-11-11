CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv_report') AS
SELECT CAST(region AS STRING) AS region,
       CAST(COUNT(*) AS BIGINT) AS customers,
       CAST(SUM(order_count) AS DECIMAL(38,0)) AS orders,
       CAST(SUM(ltv) AS DECIMAL(38,2)) AS total_ltv,
       CAST((CASE WHEN AVG(ltv) < 0 THEN CEIL(AVG(ltv) * 100)
                  ELSE FLOOR(AVG(ltv) * 100)
             END) / CAST(100 AS DECIMAL(3,0)) AS DECIMAL(38,2)) AS avg_ltv
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv')
GROUP BY region;
