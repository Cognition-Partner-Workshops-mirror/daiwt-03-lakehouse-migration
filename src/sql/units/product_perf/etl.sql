-- gold.product_perf: per-product units and revenue, plus the top three store
-- regions by units sold (port of legacy/redshift/units/product_perf/etl.sql).
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.product_perf')
USING DELTA
AS
WITH per_store AS (
    SELECT oi.product_id,
           s.region,
           SUM(oi.quantity) AS units
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
    JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o ON o.order_id = oi.order_id
    JOIN   IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') s ON s.store_id = o.store_id
    GROUP  BY oi.product_id, s.region
),
ranked AS (
    SELECT product_id, region, units,
           ROW_NUMBER() OVER (PARTITION BY product_id
                              ORDER BY units DESC NULLS FIRST, region ASC NULLS LAST) AS rn
    FROM   per_store
),
top_stores AS (
    -- LISTAGG over CHAR(4) emits unpadded codes, ordered as the ranking.
    SELECT product_id,
           CAST(array_join(
                  transform(array_sort(collect_list(named_struct('rn', rn, 'code', rtrim(region)))),
                            x -> x.code),
                  ',') AS STRING) AS codes
    FROM   ranked
    WHERE  rn <= 3
    GROUP  BY product_id
),
agg AS (
    SELECT product_id,
           CAST(SUM(quantity) AS BIGINT)                                  AS units_sold,
           CAST(SUM(quantity * (unit_price - discount)) AS DECIMAL(18,2)) AS revenue
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items')
    GROUP  BY product_id
)
SELECT p.product_id,
       p.category,
       COALESCE(a.units_sold, CAST(0 AS BIGINT))        AS units_sold,
       COALESCE(a.revenue, CAST(0 AS DECIMAL(18,2)))    AS revenue,
       ts.codes                                         AS top_stores
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
LEFT JOIN agg        a  ON a.product_id = p.product_id
LEFT JOIN top_stores ts ON ts.product_id = p.product_id;
