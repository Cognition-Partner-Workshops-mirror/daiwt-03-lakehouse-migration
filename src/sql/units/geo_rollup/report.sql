-- BI report: the rollup as published (NULL grouping columns included).
EXECUTE IMMEDIATE
  'CREATE OR REPLACE VIEW ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:gold_schema, '`', '``') || '`') || '.`report_geo_rollup` AS
   SELECT grouping_id, region, state, order_count, revenue
   FROM ' || ('`' || replace(:catalog, '`', '``') || '`.`' || replace(:gold_schema, '`', '``') || '`') || '.`geo_rollup`
   ORDER BY grouping_id, region NULLS LAST, state NULLS LAST';
