CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') AS
SELECT
    CAST(store_id AS INT) AS store_id,
    rpad(CAST(region AS STRING), 4, ' ') AS region,
    CAST(store_name AS STRING) AS store_name,
    CAST(city AS STRING) AS city,
    CAST(state AS STRING) AS state
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores');
