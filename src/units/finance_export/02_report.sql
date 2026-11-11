CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_finance_export') AS
SELECT
  CAST(fiscal_year AS INT) AS fiscal_year,
  CAST(fiscal_qtr AS STRING) AS fiscal_qtr,
  CAST(sum(order_count) AS BIGINT) AS order_count,
  CAST(sum(revenue) AS DECIMAL(38,2)) AS revenue
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.finance_monthly')
GROUP BY fiscal_year, fiscal_qtr;
