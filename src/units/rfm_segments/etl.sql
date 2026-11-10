CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.rfm_segments') AS
WITH metrics AS (
    SELECT c.customer_id,
           CAST(datediff(DATE '2025-12-31', CAST(MAX(o.order_ts) AS DATE)) AS BIGINT) AS recency_days,
           COUNT(DISTINCT o.order_id) AS frequency,
           CAST(COALESCE(SUM(oi.quantity * (oi.unit_price - oi.discount)), 0) AS DECIMAL(38,2)) AS monetary
    FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.customers') c
    LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') o
        ON o.customer_id = c.customer_id
    LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') oi
        ON oi.order_id = o.order_id
    GROUP BY c.customer_id
),
tiles AS (
    SELECT customer_id,
           recency_days,
           frequency,
           monetary,
           NTILE(5) OVER (ORDER BY recency_days ASC NULLS LAST, customer_id ASC NULLS LAST) AS r_tile,
           NTILE(5) OVER (ORDER BY frequency DESC NULLS FIRST, customer_id ASC NULLS LAST) AS f_tile,
           NTILE(5) OVER (ORDER BY monetary DESC NULLS FIRST, customer_id ASC NULLS LAST) AS m_tile
    FROM metrics
)
SELECT CAST(customer_id AS BIGINT) AS customer_id,
       recency_days,
       CAST(frequency AS BIGINT) AS frequency,
       monetary,
       CAST(r_tile AS BIGINT) AS r_tile,
       CAST(f_tile AS BIGINT) AS f_tile,
       CAST(m_tile AS BIGINT) AS m_tile,
       concat(CAST(r_tile AS STRING), CAST(f_tile AS STRING), CAST(m_tile AS STRING)) AS rfm_segment
FROM tiles;
