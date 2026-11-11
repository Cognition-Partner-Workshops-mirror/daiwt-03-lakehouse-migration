CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') AS
SELECT
    CAST(order_id AS BIGINT) AS order_id,
    CAST(customer_id AS BIGINT) AS customer_id,
    CAST(store_id AS INT) AS store_id,
    CAST(order_ts AS TIMESTAMP_NTZ) AS order_ts,
    CAST(sales_channel AS STRING) AS sales_channel,
    CAST(status AS STRING) AS status
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.orders')
WHERE _drop = :drop;
