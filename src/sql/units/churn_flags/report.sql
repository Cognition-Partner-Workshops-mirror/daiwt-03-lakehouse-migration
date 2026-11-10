-- report_churn_flags: churn flag distribution; integer AVG truncates toward zero.
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_churn_flags')
USING DELTA
AS
SELECT churn_flag,
       COUNT(*) AS customers,
       CAST(SUM(days_since_order) DIV NULLIF(COUNT(days_since_order), 0) AS BIGINT) AS avg_days_since_order
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.churn_flags')
GROUP BY churn_flag
ORDER BY churn_flag;
