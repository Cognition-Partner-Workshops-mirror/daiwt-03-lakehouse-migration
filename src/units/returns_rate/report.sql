CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_returns_rate') AS
SELECT category, sold_qty, returned_qty, return_rate_int, return_pct
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate');
