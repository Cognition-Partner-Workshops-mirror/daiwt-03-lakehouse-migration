SELECT CASE WHEN :drop RLIKE '^[A-Za-z0-9_-]+$' THEN 'Valid drop'
            ELSE raise_error('Invalid drop name') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers') (
  customer_id BIGINT NOT NULL, email STRING, first_name STRING, last_name STRING, phone STRING, region STRING, preferred_store_id INT, signup_date DATE, is_business BOOLEAN,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers') (customer_id, email, first_name, last_name, phone, region, preferred_store_id, signup_date, is_business, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(customer_id, ''), r'\N') AS BIGINT) AS customer_id,
       CAST(NULLIF(COALESCE(email, ''), r'\N') AS STRING) AS email,
       CAST(NULLIF(COALESCE(first_name, ''), r'\N') AS STRING) AS first_name,
       CAST(NULLIF(COALESCE(last_name, ''), r'\N') AS STRING) AS last_name,
       CAST(NULLIF(COALESCE(phone, ''), r'\N') AS STRING) AS phone,
       CAST(NULLIF(COALESCE(region, ''), r'\N') AS STRING) AS region,
       CAST(NULLIF(COALESCE(preferred_store_id, ''), r'\N') AS INT) AS preferred_store_id,
       CAST(NULLIF(COALESCE(signup_date, ''), r'\N') AS DATE) AS signup_date,
       CAST(NULLIF(COALESCE(is_business, ''), r'\N') AS BOOLEAN) AS is_business,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.customers.csv',
  format => 'csv', header => true,
  schema => 'customer_id STRING, email STRING, first_name STRING, last_name STRING, phone STRING, region STRING, preferred_store_id STRING, signup_date STRING, is_business STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('customers: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores') (
  store_id INT NOT NULL, region STRING, store_name STRING, city STRING, state STRING,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores') (store_id, region, store_name, city, state, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(store_id, ''), r'\N') AS INT) AS store_id,
       CAST(NULLIF(COALESCE(region, ''), r'\N') AS STRING) AS region,
       CAST(NULLIF(COALESCE(store_name, ''), r'\N') AS STRING) AS store_name,
       CAST(NULLIF(COALESCE(city, ''), r'\N') AS STRING) AS city,
       CAST(NULLIF(COALESCE(state, ''), r'\N') AS STRING) AS state,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.stores.csv',
  format => 'csv', header => true,
  schema => 'store_id STRING, region STRING, store_name STRING, city STRING, state STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('stores: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.products') (
  product_id INT NOT NULL, sku STRING, product_name STRING, category STRING, subcategory STRING, unit_price DECIMAL(12,2), cost DECIMAL(12,2), active BOOLEAN,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.products') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.products') (product_id, sku, product_name, category, subcategory, unit_price, cost, active, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(product_id, ''), r'\N') AS INT) AS product_id,
       CAST(NULLIF(COALESCE(sku, ''), r'\N') AS STRING) AS sku,
       CAST(NULLIF(COALESCE(product_name, ''), r'\N') AS STRING) AS product_name,
       CAST(NULLIF(COALESCE(category, ''), r'\N') AS STRING) AS category,
       CAST(NULLIF(COALESCE(subcategory, ''), r'\N') AS STRING) AS subcategory,
       CAST(NULLIF(COALESCE(unit_price, ''), r'\N') AS DECIMAL(12,2)) AS unit_price,
       CAST(NULLIF(COALESCE(cost, ''), r'\N') AS DECIMAL(12,2)) AS cost,
       CAST(NULLIF(COALESCE(active, ''), r'\N') AS BOOLEAN) AS active,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.products.csv',
  format => 'csv', header => true,
  schema => 'product_id STRING, sku STRING, product_name STRING, category STRING, subcategory STRING, unit_price STRING, cost STRING, active STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('products: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.orders') (
  order_id BIGINT NOT NULL, customer_id BIGINT, store_id INT, order_ts TIMESTAMP_NTZ, sales_channel STRING, status STRING,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.orders') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.orders') (order_id, customer_id, store_id, order_ts, sales_channel, status, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(order_id, ''), r'\N') AS BIGINT) AS order_id,
       CAST(NULLIF(COALESCE(customer_id, ''), r'\N') AS BIGINT) AS customer_id,
       CAST(NULLIF(COALESCE(store_id, ''), r'\N') AS INT) AS store_id,
       CAST(NULLIF(COALESCE(order_ts, ''), r'\N') AS TIMESTAMP_NTZ) AS order_ts,
       CAST(NULLIF(COALESCE(sales_channel, ''), r'\N') AS STRING) AS sales_channel,
       CAST(NULLIF(COALESCE(status, ''), r'\N') AS STRING) AS status,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.orders.csv',
  format => 'csv', header => true,
  schema => 'order_id STRING, customer_id STRING, store_id STRING, order_ts STRING, sales_channel STRING, status STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('orders: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items') (
  order_item_id BIGINT NOT NULL, order_id BIGINT, product_id INT, quantity INT, unit_price DECIMAL(12,2), discount DECIMAL(12,2),
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items') (order_item_id, order_id, product_id, quantity, unit_price, discount, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(order_item_id, ''), r'\N') AS BIGINT) AS order_item_id,
       CAST(NULLIF(COALESCE(order_id, ''), r'\N') AS BIGINT) AS order_id,
       CAST(NULLIF(COALESCE(product_id, ''), r'\N') AS INT) AS product_id,
       CAST(NULLIF(COALESCE(quantity, ''), r'\N') AS INT) AS quantity,
       CAST(NULLIF(COALESCE(unit_price, ''), r'\N') AS DECIMAL(12,2)) AS unit_price,
       CAST(NULLIF(COALESCE(discount, ''), r'\N') AS DECIMAL(12,2)) AS discount,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.order_items.csv',
  format => 'csv', header => true,
  schema => 'order_item_id STRING, order_id STRING, product_id STRING, quantity STRING, unit_price STRING, discount STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('order_items: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments') (
  payment_id BIGINT NOT NULL, order_id BIGINT, method STRING, amount DECIMAL(12,2), paid_ts TIMESTAMP_NTZ,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments') (payment_id, order_id, method, amount, paid_ts, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(payment_id, ''), r'\N') AS BIGINT) AS payment_id,
       CAST(NULLIF(COALESCE(order_id, ''), r'\N') AS BIGINT) AS order_id,
       CAST(NULLIF(COALESCE(method, ''), r'\N') AS STRING) AS method,
       CAST(NULLIF(COALESCE(amount, ''), r'\N') AS DECIMAL(12,2)) AS amount,
       CAST(NULLIF(COALESCE(paid_ts, ''), r'\N') AS TIMESTAMP_NTZ) AS paid_ts,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.payments.csv',
  format => 'csv', header => true,
  schema => 'payment_id STRING, order_id STRING, method STRING, amount STRING, paid_ts STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('payments: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns') (
  return_id BIGINT NOT NULL, order_item_id BIGINT, quantity INT, reason STRING, returned_ts TIMESTAMP_NTZ,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns') (return_id, order_item_id, quantity, reason, returned_ts, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(return_id, ''), r'\N') AS BIGINT) AS return_id,
       CAST(NULLIF(COALESCE(order_item_id, ''), r'\N') AS BIGINT) AS order_item_id,
       CAST(NULLIF(COALESCE(quantity, ''), r'\N') AS INT) AS quantity,
       CAST(NULLIF(COALESCE(reason, ''), r'\N') AS STRING) AS reason,
       CAST(NULLIF(COALESCE(returned_ts, ''), r'\N') AS TIMESTAMP_NTZ) AS returned_ts,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.returns.csv',
  format => 'csv', header => true,
  schema => 'return_id STRING, order_item_id STRING, quantity STRING, reason STRING, returned_ts STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('returns: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments') (
  shipment_id BIGINT NOT NULL, order_id BIGINT, carrier STRING, ship_ts TIMESTAMP_NTZ, delivered_ts TIMESTAMP_NTZ,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments') (shipment_id, order_id, carrier, ship_ts, delivered_ts, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(shipment_id, ''), r'\N') AS BIGINT) AS shipment_id,
       CAST(NULLIF(COALESCE(order_id, ''), r'\N') AS BIGINT) AS order_id,
       CAST(NULLIF(COALESCE(carrier, ''), r'\N') AS STRING) AS carrier,
       CAST(NULLIF(COALESCE(ship_ts, ''), r'\N') AS TIMESTAMP_NTZ) AS ship_ts,
       CAST(NULLIF(COALESCE(delivered_ts, ''), r'\N') AS TIMESTAMP_NTZ) AS delivered_ts,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.shipments.csv',
  format => 'csv', header => true,
  schema => 'shipment_id STRING, order_id STRING, carrier STRING, ship_ts STRING, delivered_ts STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('shipments: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events') (
  event_id BIGINT NOT NULL, customer_id BIGINT, event_ts TIMESTAMP_NTZ, event_type STRING, page_url STRING,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events') (event_id, customer_id, event_ts, event_type, page_url, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(event_id, ''), r'\N') AS BIGINT) AS event_id,
       CAST(NULLIF(COALESCE(customer_id, ''), r'\N') AS BIGINT) AS customer_id,
       CAST(NULLIF(COALESCE(event_ts, ''), r'\N') AS TIMESTAMP_NTZ) AS event_ts,
       CAST(NULLIF(COALESCE(event_type, ''), r'\N') AS STRING) AS event_type,
       CAST(NULLIF(COALESCE(page_url, ''), r'\N') AS STRING) AS page_url,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.web_events.csv',
  format => 'csv', header => true,
  schema => 'event_id STRING, customer_id STRING, event_ts STRING, event_type STRING, page_url STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('web_events: invalid CSV row') END;

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches') (
  touch_id BIGINT NOT NULL, customer_id BIGINT, payload STRING,
  _drop STRING,
  _loaded_at TIMESTAMP
) USING DELTA;

DELETE FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches') WHERE _drop = :drop;

INSERT INTO IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches') (touch_id, customer_id, payload, _drop, _loaded_at)
SELECT CAST(NULLIF(COALESCE(touch_id, ''), r'\N') AS BIGINT) AS touch_id,
       CAST(NULLIF(COALESCE(customer_id, ''), r'\N') AS BIGINT) AS customer_id,
       CAST(NULLIF(COALESCE(payload, ''), r'\N') AS STRING) AS payload,
       :drop, current_timestamp()
FROM read_files(
  :golden_path || '/inputs/' || :drop || '/core.campaign_touches.csv',
  format => 'csv', header => true,
  schema => 'touch_id STRING, customer_id STRING, payload STRING',
  nullValue => '', emptyValue => '',
  quote => '"', escape => '"', multiLine => true,
  ignoreLeadingWhiteSpace => false, ignoreTrailingWhiteSpace => false,
  mode => 'FAILFAST', enforceSchema => false,
  schemaEvolutionMode => 'rescue', rescuedDataColumn => '_rescued_data', readerCaseSensitive => true
)
WHERE CASE WHEN _rescued_data IS NULL THEN true
           ELSE raise_error('campaign_touches: invalid CSV row') END;
