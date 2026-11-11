CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.geo_rollup_report') AS
SELECT grouping_id, region, state, order_count, revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.geo_rollup');
