CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.payment_mix') AS
WITH method_totals AS (
  SELECT
    method,
    COUNT(*) AS payment_count,
    SUM(CAST(amount AS DECIMAL(12, 2))) AS amount_total
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.payments')
  GROUP BY method
), method_shares AS (
  SELECT *, amount_total / SUM(amount_total) OVER () AS amount_share
  FROM method_totals
)
SELECT
  CAST(COALESCE(method, 'unknown') AS STRING) AS method,
  CAST(CASE COALESCE(method, 'unknown')
    WHEN 'card' THEN 'CARD'
    WHEN 'cash' THEN 'CASH'
    WHEN 'wallet' THEN 'DIGITAL'
    WHEN 'gift_card' THEN 'DIGITAL'
    ELSE 'OTHER'
  END AS STRING) AS method_family,
  CAST(CASE WHEN method IS NOT NULL THEN 'captured' ELSE 'missing' END AS STRING) AS method_status,
  CAST(payment_count AS BIGINT) AS payment_count,
  CAST(amount_total AS DECIMAL(38, 2)) AS amount_total,
  CAST(CASE WHEN amount_share < 0 THEN CEIL(amount_share, 4)
    ELSE FLOOR(amount_share, 4) END AS DECIMAL(38, 4)) AS amount_share
FROM method_shares;
