CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.product_perf') AS
WITH per_store AS (
    SELECT oi.product_id,
           s.region,
           SUM(oi.quantity) AS units
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
    JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
      ON o.order_id = oi.order_id
    JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') s
      ON s.store_id = o.store_id
    GROUP BY oi.product_id, s.region
),
ranked AS (
    SELECT product_id, region,
           ROW_NUMBER() OVER (
               PARTITION BY product_id
               ORDER BY units DESC NULLS FIRST, region ASC NULLS LAST
           ) AS rn
    FROM per_store
),
top_stores AS (
    SELECT product_id,
           array_join(
               transform(
                   array_sort(collect_list(struct(rn AS rank, rtrim(region) AS val))),
                   x -> x.val
               ), ','
           ) AS codes
    FROM ranked
    WHERE rn <= 3 AND region IS NOT NULL
    GROUP BY product_id
),
agg AS (
    SELECT product_id,
           CAST(SUM(quantity) AS BIGINT) AS units_sold,
           CAST(SUM(quantity * (unit_price - discount)) AS DECIMAL(18,2)) AS revenue
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items')
    GROUP BY product_id
)
SELECT CAST(p.product_id AS INT) AS product_id,
       CAST(p.category AS STRING) AS category,
       CAST(COALESCE(a.units_sold, 0) AS BIGINT) AS units_sold,
       CAST(COALESCE(a.revenue, 0) AS DECIMAL(18,2)) AS revenue,
       CAST(ts.codes AS STRING) AS top_stores
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.products') p
LEFT JOIN agg a ON a.product_id = p.product_id
LEFT JOIN top_stores ts ON ts.product_id = p.product_id
ORDER BY p.product_id ASC NULLS LAST;
