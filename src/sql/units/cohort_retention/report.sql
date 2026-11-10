CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_cohort_retention')
USING DELTA
AS
SELECT cohort_month,
       month_offset,
       cohort_size,
       active_buyers,
       ROUND(100.0 * active_buyers / cohort_size, 2) AS retention_pct
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.cohort_retention');
