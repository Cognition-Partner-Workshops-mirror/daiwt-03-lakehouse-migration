SELECT CASE WHEN COUNT(*) = COUNT(DISTINCT customer_id)
                 AND count_if(ltv IS NULL OR order_count IS NULL OR length(region) <> 4) = 0
            THEN 'PASS customer_ltv: customer grain and required values'
            ELSE raise_error('customer_ltv invariant mismatch') END AS self_check
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv');

SELECT CASE WHEN
  (SELECT COALESCE(SUM(customers), 0)
   FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.report_customer_ltv')) =
  (SELECT COUNT(*) FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.customer_ltv'))
  THEN 'PASS report_customer_ltv: customer count'
  ELSE raise_error('report_customer_ltv customer count mismatch') END AS self_check;
