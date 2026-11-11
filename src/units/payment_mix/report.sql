CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.payment_mix_report') AS
SELECT
  CAST(method_family AS STRING) AS method_family,
  CAST(SUM(payment_count) AS BIGINT) AS payment_count,
  CAST(SUM(amount_total) AS DECIMAL(38, 2)) AS amount_total
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.payment_mix')
GROUP BY method_family;
