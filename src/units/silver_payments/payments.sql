CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.payments') AS
SELECT
  CAST(payment_id AS BIGINT) AS payment_id,
  CAST(order_id AS BIGINT) AS order_id,
  CAST(method AS STRING) AS method,
  CAST(amount AS DECIMAL(12, 2)) AS amount,
  CAST(paid_ts AS TIMESTAMP_NTZ) AS paid_ts
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments')
WHERE _drop = :drop;
