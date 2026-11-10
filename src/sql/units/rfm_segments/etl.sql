CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.rfm_segments')
USING DELTA
AS
WITH metrics AS (
    SELECT c.customer_id,
           CAST(DATEDIFF(DATE'2025-12-31', CAST(MAX(o.order_ts) AS DATE)) AS BIGINT)   AS recency_days,
           CAST(COUNT(DISTINCT o.order_id) AS BIGINT)                                 AS frequency,
           CAST(COALESCE(SUM(oi.quantity * (oi.unit_price - oi.discount)), 0) AS DECIMAL(38,2)) AS monetary
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.customers') c
    LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
           ON o.customer_id = c.customer_id
    LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
           ON oi.order_id = o.order_id
    GROUP  BY c.customer_id
),
tiles AS (
    SELECT customer_id,
           recency_days,
           frequency,
           monetary,
           CAST(NTILE(5) OVER (ORDER BY recency_days ASC NULLS LAST, customer_id ASC) AS BIGINT) AS r_tile,
           CAST(NTILE(5) OVER (ORDER BY frequency DESC NULLS FIRST, customer_id ASC) AS BIGINT)  AS f_tile,
           CAST(NTILE(5) OVER (ORDER BY monetary DESC NULLS FIRST, customer_id ASC) AS BIGINT)   AS m_tile
    FROM   metrics
)
SELECT customer_id,
       recency_days,
       frequency,
       monetary,
       r_tile,
       f_tile,
       m_tile,
       CAST(r_tile AS STRING) || CAST(f_tile AS STRING) || CAST(m_tile AS STRING) AS rfm_segment
FROM   tiles;
