CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_store_weekly') AS
SELECT
  CAST(s.store_id AS INT) AS store_id,
  CAST(s.region AS STRING) AS region,
  CAST((datediff(max(w.week_start), min(w.week_start)) DIV 7) + 1 AS BIGINT) AS active_weeks,
  CAST(sum(w.order_count) AS BIGINT) AS order_count,
  CAST(sum(w.revenue) AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.store_weekly') w
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') s
  ON s.store_id = w.store_id
GROUP BY s.store_id, s.region;
