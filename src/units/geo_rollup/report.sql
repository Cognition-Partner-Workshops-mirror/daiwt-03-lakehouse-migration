CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_geo_rollup') AS
SELECT grouping_id, region, state, order_count, revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.geo_rollup')
ORDER BY grouping_id, region, state;
