-- BI report: category mix as published.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_category_mix') AS
SELECT category, units_sold, revenue, revenue_share
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.category_mix');
