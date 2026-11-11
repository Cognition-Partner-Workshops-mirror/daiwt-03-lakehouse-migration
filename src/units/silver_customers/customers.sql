CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.customers') AS
SELECT
    CAST(customer_id AS BIGINT) AS customer_id,
    CAST(email AS STRING) AS email,
    CAST(first_name AS STRING) AS first_name,
    CAST(last_name AS STRING) AS last_name,
    CAST(phone AS STRING) AS phone,
    CAST(rpad(CAST(region AS STRING), 4, ' ') AS STRING) AS region,
    CAST(preferred_store_id AS INT) AS preferred_store_id,
    CAST(signup_date AS DATE) AS signup_date,
    CAST(is_business AS BOOLEAN) AS is_business
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers')
WHERE _drop = :drop;
