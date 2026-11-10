WITH seq_cases(d, expected) AS (
  VALUES ('D0', 0), ('D12', 12), ('D01', 1), ('D2147483647', 2147483647),
         ('D2147483648', NULL), ('d1', NULL), ('D-1', NULL), (' D1', NULL),
         ('D1x', NULL), ('D1 ', NULL), (concat('D1', chr(10)), NULL), ('', NULL), (NULL, NULL)
), seq_check AS (
  SELECT bool_and(IDENTIFIER(:catalog || '.' || :silver_schema || '.drop_seq')(d) <=> expected) AS ok
  FROM seq_cases
), loaded AS (
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.products')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.orders')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events')
  UNION ALL
  SELECT _drop, _loaded_at FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches')
), candidates AS (
  SELECT _drop, IDENTIFIER(:catalog || '.' || :silver_schema || '.drop_seq')(_drop) AS seq,
         max(_loaded_at) AS loaded_at
  FROM loaded GROUP BY _drop
), resolved AS (
  SELECT _drop FROM candidates
  WHERE seq <= IDENTIFIER(:catalog || '.' || :silver_schema || '.drop_seq')(:drop)
  ORDER BY seq DESC, loaded_at DESC, _drop DESC LIMIT 1
), effective AS (
  SELECT (SELECT _drop FROM resolved) AS resolved_drop
), actual AS (
  SELECT 'customers' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_customers')(:drop)
  UNION ALL
  SELECT 'stores' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_stores')(:drop)
  UNION ALL
  SELECT 'products' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_products')(:drop)
  UNION ALL
  SELECT 'orders' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_orders')(:drop)
  UNION ALL
  SELECT 'order_items' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_order_items')(:drop)
  UNION ALL
  SELECT 'payments' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_payments')(:drop)
  UNION ALL
  SELECT 'returns' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_returns')(:drop)
  UNION ALL
  SELECT 'shipments' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_shipments')(:drop)
  UNION ALL
  SELECT 'web_events' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_web_events')(:drop)
  UNION ALL
  SELECT 'campaign_touches' AS table_name,
         count(*) AS actual_rows FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_campaign_touches')(:drop)
), expected AS (
  SELECT 'customers' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'stores' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'products' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.products')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'orders' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.orders')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'order_items' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'payments' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'returns' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'shipments' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'web_events' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events')
  WHERE _drop = (SELECT resolved_drop FROM effective)
  UNION ALL
  SELECT 'campaign_touches' AS table_name, count(*) AS expected_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches')
  WHERE _drop = (SELECT resolved_drop FROM effective)
), bronze_columns AS (
  SELECT table_name,
         transform(sort_array(collect_list(struct(ordinal_position, column_name,
                   regexp_replace(lower(full_data_type), ' collate utf8_binary$', '') AS kind))),
                   column -> named_struct('name', column.column_name, 'kind', column.kind)) AS business_columns
  FROM IDENTIFIER(:catalog || '.information_schema.columns')
  WHERE table_schema = :bronze_schema AND column_name NOT IN ('_drop', '_loaded_at')
  GROUP BY table_name
), function_columns AS (
  SELECT routines.routine_name,
         transform(sort_array(collect_list(struct(cols.ordinal_position, cols.column_name,
                   regexp_replace(lower(cols.full_data_type), ' collate utf8_binary$', '') AS kind))),
                   column -> named_struct('name', column.column_name, 'kind', column.kind)) AS business_columns
  FROM IDENTIFIER(:catalog || '.information_schema.routine_columns') AS cols
  JOIN IDENTIFIER(:catalog || '.information_schema.routines') AS routines
    ON cols.specific_catalog = routines.specific_catalog
   AND cols.specific_schema = routines.specific_schema
   AND cols.specific_name = routines.specific_name
  WHERE routines.routine_schema = :silver_schema
  GROUP BY routines.routine_name
)
SELECT actual.table_name, resolved_drop, actual_rows, expected_rows,
       CASE WHEN (SELECT ok FROM seq_check) AND actual_rows = expected_rows
                 AND (resolved_drop <=> IDENTIFIER(:catalog || '.' || :silver_schema || '.resolve_drop')(:drop))
                 AND bronze_columns.business_columns = function_columns.business_columns
            THEN 'PASS'
            ELSE raise_error(concat('silver_asof mismatch: ', actual.table_name,
                                   ' (resolved drop, snapshot count or ordered business columns/types)')) END AS status
FROM actual
JOIN expected USING (table_name)
CROSS JOIN effective
LEFT JOIN bronze_columns USING (table_name)
LEFT JOIN function_columns ON function_columns.routine_name = 'asof_' || actual.table_name
ORDER BY actual.table_name;
