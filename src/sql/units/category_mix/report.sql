CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_category_mix')
USING DELTA
AS
SELECT category, units_sold, revenue, revenue_share
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.category_mix');
