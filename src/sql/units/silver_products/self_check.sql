SELECT CASE WHEN :silver_bad_rows = 'true' OR count(*) = 0 THEN true
  ELSE raise_error('products_quarantine is not empty') END
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.products_quarantine');

SELECT CASE WHEN
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.products')) =
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_products')(:drop))
  THEN true ELSE raise_error('products asof row count mismatch') END;

SELECT CASE WHEN count(*) = 0 THEN true
  ELSE raise_error('products has NULL product_id') END
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.products')
WHERE product_id IS NULL;
