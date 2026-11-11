CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.store_weekly_report') AS
SELECT CAST(s.store_id AS INT)                                                     AS store_id,
       s.region                                                                    AS region,
       CAST(DATEDIFF(MAX(w.week_start), MIN(w.week_start)) DIV 7 + 1 AS BIGINT)    AS active_weeks,
       CAST(SUM(w.order_count) AS BIGINT)                                          AS order_count,
       SUM(w.revenue)                                                              AS revenue
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.store_weekly') w
JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') s ON s.store_id = w.store_id
GROUP  BY s.store_id, s.region;
