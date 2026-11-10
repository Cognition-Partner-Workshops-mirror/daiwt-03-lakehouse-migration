WITH manifest AS (
  SELECT entry.path, entry.row_count,
         transform(entry.columns, column -> column.name) AS columns
  FROM read_files(:golden_path || '/manifest.json', format => 'json', multiLine => true,
                  mode => 'FAILFAST'),
       LATERAL explode(files) AS entries(entry)
  WHERE entry.path LIKE 'inputs/' || :drop || '/core.%.csv'
), expected AS (
  SELECT path, count(*) AS entries, max(row_count) AS expected_rows,
         first(columns) AS expected_columns
  FROM manifest GROUP BY path
), actual AS (
  SELECT 'customers' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers') WHERE _drop = :drop
  UNION ALL
  SELECT 'stores' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.stores') WHERE _drop = :drop
  UNION ALL
  SELECT 'products' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.products') WHERE _drop = :drop
  UNION ALL
  SELECT 'orders' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.orders') WHERE _drop = :drop
  UNION ALL
  SELECT 'order_items' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.order_items') WHERE _drop = :drop
  UNION ALL
  SELECT 'payments' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.payments') WHERE _drop = :drop
  UNION ALL
  SELECT 'returns' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.returns') WHERE _drop = :drop
  UNION ALL
  SELECT 'shipments' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.shipments') WHERE _drop = :drop
  UNION ALL
  SELECT 'web_events' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.web_events') WHERE _drop = :drop
  UNION ALL
  SELECT 'campaign_touches' AS table_name, count(*) AS actual_rows
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.campaign_touches') WHERE _drop = :drop
), columns AS (
  SELECT table_name,
         transform(sort_array(collect_list(struct(ordinal_position, column_name))),
                   column -> column.column_name) AS actual_columns
  FROM IDENTIFIER(:catalog || '.information_schema.columns')
  WHERE table_schema = :bronze_schema
  GROUP BY table_name
)
SELECT actual.table_name, actual_rows, expected_rows, actual_columns,
       CASE WHEN entries = 1 AND (SELECT count(*) FROM manifest) = 10
                 AND actual_rows = expected_rows
                 AND actual_columns = concat(expected_columns, array('_drop', '_loaded_at'))
            THEN 'PASS'
            ELSE raise_error(concat('bronze_landing mismatch: ', actual.table_name,
                                   ' (manifest count, row count or ordered columns)')) END AS status
FROM actual
LEFT JOIN expected ON expected.path = 'inputs/' || :drop || '/core.' || actual.table_name || '.csv'
LEFT JOIN columns ON columns.table_name = actual.table_name
ORDER BY actual.table_name;
