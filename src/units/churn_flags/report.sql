CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.churn_flags_report') AS
SELECT CAST(churn_flag AS STRING) AS churn_flag,
       CAST(COUNT(*) AS BIGINT) AS customers,
       CAST(CASE WHEN AVG(days_since_order) < 0
                 THEN CEIL(AVG(days_since_order))
                 ELSE FLOOR(AVG(days_since_order))
            END AS BIGINT) AS avg_days_since_order
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.churn_flags')
GROUP BY churn_flag
ORDER BY churn_flag;
