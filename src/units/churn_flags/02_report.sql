CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_churn_flags') AS
SELECT
  CAST(churn_flag AS STRING) AS churn_flag,
  CAST(COUNT(*) AS BIGINT) AS customers,
  CAST(SUM(days_since_order) DIV NULLIF(COUNT(days_since_order), 0) AS BIGINT) AS avg_days_since_order
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.churn_flags')
GROUP BY churn_flag;
