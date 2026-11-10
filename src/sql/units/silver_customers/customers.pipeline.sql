CREATE TEMPORARY VIEW customers_candidates AS
SELECT customer_id, email, first_name, last_name, phone,
       rpad(region, 4, ' ') AS region, preferred_store_id, signup_date, is_business
FROM ${catalog}.${silver_schema}.asof_customers(:drop)
UNION ALL
SELECT CAST(NULL AS BIGINT), CAST('dev-only@example.invalid' AS STRING),
       CAST('Dev' AS STRING), CAST('Only' AS STRING), CAST(NULL AS STRING),
       CAST('NE  ' AS STRING), CAST(NULL AS INT), CAST('2025-12-31' AS DATE),
       CAST(false AS BOOLEAN)
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW customers (
  CONSTRAINT valid_key EXPECT (customer_id IS NOT NULL) ON VIOLATION DROP ROW
)
AS SELECT customer_id, email, first_name, last_name, phone, region,
          preferred_store_id, signup_date, is_business
FROM customers_candidates;

CREATE OR REFRESH MATERIALIZED VIEW customers_quarantine AS
SELECT *, 'null key' AS reason FROM customers_candidates WHERE customer_id IS NULL;
