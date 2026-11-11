CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.category_mix_report') AS
SELECT category, units_sold, revenue, revenue_share
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.category_mix')
ORDER BY revenue DESC, category;
