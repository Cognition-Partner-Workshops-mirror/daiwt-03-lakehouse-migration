CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.payment_mix') AS
SELECT
  CAST(COALESCE(p.method, 'unknown') AS STRING) AS method,
  CAST(CASE COALESCE(p.method, 'unknown')
    WHEN 'card' THEN 'CARD'
    WHEN 'cash' THEN 'CASH'
    WHEN 'wallet' THEN 'DIGITAL'
    WHEN 'gift_card' THEN 'DIGITAL'
    ELSE 'OTHER'
  END AS STRING) AS method_family,
  CAST(CASE WHEN p.method IS NOT NULL THEN 'captured' ELSE 'missing' END AS STRING) AS method_status,
  CAST(COUNT(*) AS BIGINT) AS payment_count,
  CAST(SUM(p.amount) AS DECIMAL(38,2)) AS amount_total,
  CAST(FLOOR(SUM(p.amount) / SUM(SUM(p.amount)) OVER (), 4) AS DECIMAL(38,4)) AS amount_share
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.payments') p
GROUP BY p.method;
