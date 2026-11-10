# Customer lifetime value

`customer_ltv` reads the published silver customers, orders and order_items
tables and calls `sql_macros.f_clean_phone` in the silver schema. The registry
requires all three silver entity units and `sql_macros` before this job.

The SQL-file tasks replace `gold.customer_ltv`, create the region summary view
`gold.report_customer_ltv`, then check customer grain and report counts. Cleanup
supports views. Catalog and layer schemas are bundle parameters; permissions
and execution identity are inherited from the bundle. The job accepts `drop`
(default `D0`); upstream silver jobs select the snapshot.

Customer-led LEFT JOINs retain customers without orders or items. Region strings
are padded to four characters and NULL phones remain NULL. Order count is
distinct orders, LTV is quantity-weighted net item revenue (zero without items),
and AOV is the unweighted item-line net unit price average (NULL without items).
Both AOV and report average LTV truncate toward zero to scale two; monetary
outputs are DECIMAL(38,2). The report counts every customer in its padded region.

The view DDL embeds escaped catalog/schema identifiers with EXECUTE IMMEDIATE
so the stored definition contains no parameter markers. Each SQL statement is
self-contained and requires no shared task session.
