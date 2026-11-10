CREATE TEMPORARY VIEW stores_candidates AS
SELECT store_id, rpad(region, 4, ' ') AS region, store_name, city, state
FROM ${catalog}.${silver_schema}.asof_stores(:drop)
UNION ALL
SELECT CAST(NULL AS INT), CAST('NE  ' AS STRING), CAST('Synthetic null-key store' AS STRING), CAST('Nowhere' AS STRING), CAST('ZZ' AS STRING)
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW stores (
  CONSTRAINT valid_store_id EXPECT (store_id IS NOT NULL) ON VIOLATION DROP ROW
)
AS SELECT store_id, region, store_name, city, state FROM stores_candidates;

CREATE OR REFRESH MATERIALIZED VIEW stores_quarantine AS
SELECT *, 'null store_id' AS reason FROM stores_candidates WHERE store_id IS NULL;
