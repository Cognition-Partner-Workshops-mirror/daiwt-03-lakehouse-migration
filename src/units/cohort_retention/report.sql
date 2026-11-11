CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.cohort_retention_report') AS
SELECT CAST(cohort_month AS DATE) AS cohort_month,
       CAST(month_offset AS INT) AS month_offset,
       CAST(cohort_size AS BIGINT) AS cohort_size,
       CAST(active_buyers AS BIGINT) AS active_buyers,
       CAST(ROUND(CAST(100.0 AS DECIMAL(4, 1)) * active_buyers / cohort_size, 2)
            AS DECIMAL(38, 2)) AS retention_pct
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.cohort_retention');
