CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_store_weekly') AS
SELECT CAST(s.store_id AS INT) AS store_id,
       RPAD(s.region, 4, ' ') AS region,
       CAST((DATEDIFF(CAST(DATE_TRUNC('WEEK', MAX(w.week_start)) AS DATE),
                      CAST(DATE_TRUNC('WEEK', MIN(w.week_start)) AS DATE)) DIV 7) + 1 AS BIGINT) AS active_weeks,
       CAST(SUM(w.order_count) AS BIGINT) AS order_count,
       CAST(SUM(w.revenue) AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.store_weekly') w
JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') s
  ON s.store_id = w.store_id
GROUP BY s.store_id, s.region;
