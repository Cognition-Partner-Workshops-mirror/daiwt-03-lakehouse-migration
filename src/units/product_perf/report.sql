CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_product_perf') AS
SELECT CAST(category AS STRING) AS category,
       CAST(COUNT(*) AS BIGINT) AS products,
       CAST(SUM(units_sold) AS BIGINT) AS units_sold,
       CAST(SUM(revenue) AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.product_perf')
GROUP BY category
ORDER BY category ASC NULLS LAST;
