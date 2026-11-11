CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.returns') AS
SELECT
  CAST(return_id AS BIGINT) AS return_id,
  CAST(order_item_id AS BIGINT) AS order_item_id,
  CAST(quantity AS INT) AS quantity,
  CAST(reason AS STRING) AS reason,
  CAST(returned_ts AS TIMESTAMP_NTZ) AS returned_ts
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns')
WHERE _drop = :drop;
