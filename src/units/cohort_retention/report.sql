CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_cohort_retention') AS
SELECT cohort_month,
       month_offset,
       cohort_size,
       active_buyers,
       CAST(ROUND(CAST(100.0 AS DECIMAL(4,1)) * active_buyers / cohort_size, 2) AS DECIMAL(38,2)) AS retention_pct
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.cohort_retention');
