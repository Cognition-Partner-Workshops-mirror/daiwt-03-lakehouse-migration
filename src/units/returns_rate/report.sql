CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate_report') AS
SELECT category, sold_qty, returned_qty, return_rate_int, return_pct
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.returns_rate')
ORDER BY return_pct DESC NULLS FIRST, category ASC NULLS LAST;
