CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_geo_rollup') AS
SELECT
  CAST(grouping_id AS INT) AS grouping_id,
  CAST(region AS STRING) AS region,
  CAST(state AS STRING) AS state,
  CAST(order_count AS BIGINT) AS order_count,
  CAST(revenue AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.geo_rollup');
