CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :silver_schema || '.drop_seq')(d STRING)
RETURNS INT
DETERMINISTIC
RETURN CASE WHEN d RLIKE r'^D[0-9]+\z' THEN try_cast(substring(d, 2) AS INT) ELSE NULL END;

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop STRING)
   RETURNS STRING
   RETURN (
     WITH loaded AS (
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`customers`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`stores`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`products`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`orders`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`order_items`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`payments`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`returns`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`shipments`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`web_events`
       UNION ALL
       SELECT _drop, _loaded_at FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`campaign_touches`
     ), candidates AS (
       SELECT _drop, ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`drop_seq`(_drop) AS seq, max(_loaded_at) AS loaded_at
       FROM loaded GROUP BY _drop
     )
     SELECT _drop FROM candidates
     WHERE seq <= ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`drop_seq`(as_of_drop)
     ORDER BY seq DESC, loaded_at DESC, _drop DESC
     LIMIT 1
   )';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_customers`(as_of_drop STRING)
   RETURNS TABLE (customer_id BIGINT, email STRING, first_name STRING, last_name STRING, phone STRING, region STRING, preferred_store_id INT, signup_date DATE, is_business BOOLEAN)
   RETURN
     SELECT customer_id, email, first_name, last_name, phone, region, preferred_store_id, signup_date, is_business
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`customers`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_stores`(as_of_drop STRING)
   RETURNS TABLE (store_id INT, region STRING, store_name STRING, city STRING, state STRING)
   RETURN
     SELECT store_id, region, store_name, city, state
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`stores`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_products`(as_of_drop STRING)
   RETURNS TABLE (product_id INT, sku STRING, product_name STRING, category STRING, subcategory STRING, unit_price DECIMAL(12,2), cost DECIMAL(12,2), active BOOLEAN)
   RETURN
     SELECT product_id, sku, product_name, category, subcategory, unit_price, cost, active
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`products`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_orders`(as_of_drop STRING)
   RETURNS TABLE (order_id BIGINT, customer_id BIGINT, store_id INT, order_ts TIMESTAMP_NTZ, sales_channel STRING, status STRING)
   RETURN
     SELECT order_id, customer_id, store_id, order_ts, sales_channel, status
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`orders`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_order_items`(as_of_drop STRING)
   RETURNS TABLE (order_item_id BIGINT, order_id BIGINT, product_id INT, quantity INT, unit_price DECIMAL(12,2), discount DECIMAL(12,2))
   RETURN
     SELECT order_item_id, order_id, product_id, quantity, unit_price, discount
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`order_items`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_payments`(as_of_drop STRING)
   RETURNS TABLE (payment_id BIGINT, order_id BIGINT, method STRING, amount DECIMAL(12,2), paid_ts TIMESTAMP_NTZ)
   RETURN
     SELECT payment_id, order_id, method, amount, paid_ts
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`payments`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_returns`(as_of_drop STRING)
   RETURNS TABLE (return_id BIGINT, order_item_id BIGINT, quantity INT, reason STRING, returned_ts TIMESTAMP_NTZ)
   RETURN
     SELECT return_id, order_item_id, quantity, reason, returned_ts
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`returns`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_shipments`(as_of_drop STRING)
   RETURNS TABLE (shipment_id BIGINT, order_id BIGINT, carrier STRING, ship_ts TIMESTAMP_NTZ, delivered_ts TIMESTAMP_NTZ)
   RETURN
     SELECT shipment_id, order_id, carrier, ship_ts, delivered_ts
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`shipments`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_web_events`(as_of_drop STRING)
   RETURNS TABLE (event_id BIGINT, customer_id BIGINT, event_ts TIMESTAMP_NTZ, event_type STRING, page_url STRING)
   RETURN
     SELECT event_id, customer_id, event_ts, event_type, page_url
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`web_events`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';

EXECUTE IMMEDIATE
  'CREATE OR REPLACE FUNCTION ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`asof_campaign_touches`(as_of_drop STRING)
   RETURNS TABLE (touch_id BIGINT, customer_id BIGINT, payload STRING)
   RETURN
     SELECT touch_id, customer_id, payload
     FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:bronze_schema, '`', '``') || '`') || '.`campaign_touches`
     WHERE _drop = ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:silver_schema, '`', '``') || '`') || '.`resolve_drop`(as_of_drop)';
