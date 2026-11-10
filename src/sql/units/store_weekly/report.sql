CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_store_weekly')
USING DELTA
AS
SELECT s.store_id                                                         AS store_id,
       rpad(s.region, 4, ' ')                                             AS region,
       CAST(datediff(MAX(w.week_start), MIN(w.week_start)) DIV 7 + 1 AS BIGINT) AS active_weeks,
       CAST(SUM(w.order_count) AS BIGINT)                                 AS order_count,
       CAST(SUM(w.revenue) AS DECIMAL(38,2))                              AS revenue
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.store_weekly') w
JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') s
       ON s.store_id = w.store_id
GROUP  BY s.store_id, rpad(s.region, 4, ' ');
