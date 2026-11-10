EXECUTE IMMEDIATE
  'CREATE OR REPLACE VIEW `' || replace(:catalog, '`', '``') || '`.`' ||
  replace(:gold_schema, '`', '``') || '`.`report_customer_ltv` AS
   SELECT region,
          COUNT(*) AS customers,
          CAST(SUM(order_count) AS BIGINT) AS orders,
          CAST(SUM(ltv) AS DECIMAL(38,2)) AS total_ltv,
          CAST(sign(AVG(ltv)) * floor(abs(AVG(ltv)), 2) AS DECIMAL(38,2)) AS avg_ltv
   FROM `' || replace(:catalog, '`', '``') || '`.`' ||
  replace(:gold_schema, '`', '``') || '`.`customer_ltv`
   GROUP BY region';
