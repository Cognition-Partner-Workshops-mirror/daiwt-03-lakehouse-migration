SELECT CASE WHEN :silver_bad_rows = 'true' OR count(*) = 0 THEN true
  ELSE raise_error('orders_quarantine is not empty') END
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders_quarantine');

SELECT CASE WHEN
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders')) =
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_orders')(:drop))
  THEN true ELSE raise_error('orders asof row count mismatch') END;

SELECT CASE WHEN count(*) = 0 THEN true
  ELSE raise_error('orders has NULL order_id') END
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.orders')
WHERE order_id IS NULL;
