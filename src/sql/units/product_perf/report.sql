-- gold.report_product_perf: category performance BI report
-- (port of legacy/redshift/units/product_perf/report.sql).
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_product_perf')
USING DELTA
AS
SELECT category,
       COUNT(*)                                    AS products,
       CAST(SUM(units_sold) AS BIGINT)             AS units_sold,
       CAST(SUM(revenue) AS DECIMAL(38,2))         AS revenue
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.product_perf')
GROUP  BY category;
