CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_returns_rate') AS
SELECT
  CAST(category AS STRING) AS category,
  CAST(sold_qty AS BIGINT) AS sold_qty,
  CAST(returned_qty AS BIGINT) AS returned_qty,
  CAST(return_rate_int AS BIGINT) AS return_rate_int,
  CAST(return_pct AS DECIMAL(33,15)) AS return_pct
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate')
ORDER BY return_pct DESC, category;
