-- Typed silver copies of the core landing tables (legacy load_core table group).
-- CHAR(4) regions keep blank padding; SUPER payload stays verbatim JSON text.

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.customers') AS
SELECT
  CAST(customer_id AS BIGINT) AS customer_id,
  CAST(email AS STRING) AS email,
  CAST(first_name AS STRING) AS first_name,
  CAST(last_name AS STRING) AS last_name,
  CAST(phone AS STRING) AS phone,
  CAST(rpad(region, 4, ' ') AS STRING) AS region,
  CAST(preferred_store_id AS INT) AS preferred_store_id,
  CAST(signup_date AS DATE) AS signup_date,
  CAST(is_business AS BOOLEAN) AS is_business
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers')
WHERE _drop = :drop;

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') AS
SELECT
  CAST(store_id AS INT) AS store_id,
  CAST(rpad(region, 4, ' ') AS STRING) AS region,
  CAST(store_name AS STRING) AS store_name,
  CAST(city AS STRING) AS city,
  CAST(state AS STRING) AS state
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores')
WHERE _drop = :drop;

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.products') AS
SELECT
  CAST(product_id AS INT) AS product_id,
  CAST(sku AS STRING) AS sku,
  CAST(product_name AS STRING) AS product_name,
  CAST(category AS STRING) AS category,
  CAST(subcategory AS STRING) AS subcategory,
  CAST(unit_price AS DECIMAL(12,2)) AS unit_price,
  CAST(cost AS DECIMAL(12,2)) AS cost,
  CAST(active AS BOOLEAN) AS active
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.products')
WHERE _drop = :drop;

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

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') AS
SELECT
  CAST(order_item_id AS BIGINT) AS order_item_id,
  CAST(order_id AS BIGINT) AS order_id,
  CAST(product_id AS INT) AS product_id,
  CAST(quantity AS INT) AS quantity,
  CAST(unit_price AS DECIMAL(12,2)) AS unit_price,
  CAST(discount AS DECIMAL(12,2)) AS discount
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items')
WHERE _drop = :drop;

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.payments') AS
SELECT
  CAST(payment_id AS BIGINT) AS payment_id,
  CAST(order_id AS BIGINT) AS order_id,
  CAST(method AS STRING) AS method,
  CAST(amount AS DECIMAL(12,2)) AS amount,
  CAST(paid_ts AS TIMESTAMP_NTZ) AS paid_ts
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments')
WHERE _drop = :drop;

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.returns') AS
SELECT
  CAST(return_id AS BIGINT) AS return_id,
  CAST(order_item_id AS BIGINT) AS order_item_id,
  CAST(quantity AS INT) AS quantity,
  CAST(reason AS STRING) AS reason,
  CAST(returned_ts AS TIMESTAMP_NTZ) AS returned_ts
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns')
WHERE _drop = :drop;

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.shipments') AS
SELECT
  CAST(shipment_id AS BIGINT) AS shipment_id,
  CAST(order_id AS BIGINT) AS order_id,
  CAST(carrier AS STRING) AS carrier,
  CAST(ship_ts AS TIMESTAMP_NTZ) AS ship_ts,
  CAST(delivered_ts AS TIMESTAMP_NTZ) AS delivered_ts
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments')
WHERE _drop = :drop;

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.web_events') AS
SELECT
  CAST(event_id AS BIGINT) AS event_id,
  CAST(customer_id AS BIGINT) AS customer_id,
  CAST(event_ts AS TIMESTAMP_NTZ) AS event_ts,
  CAST(event_type AS STRING) AS event_type,
  CAST(page_url AS STRING) AS page_url
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events')
WHERE _drop = :drop;

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.campaign_touches') AS
SELECT
  CAST(touch_id AS BIGINT) AS touch_id,
  CAST(customer_id AS BIGINT) AS customer_id,
  CAST(payload AS STRING) AS payload
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches')
WHERE _drop = :drop;
