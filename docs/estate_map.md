# daiwt_03 estate map

Legacy estate: [daiwt-03-redshift](https://github.com/Cognition-Partner-Workshops-mirror/daiwt-03-redshift) (Redshift Serverless `daiwt_03_retail`, schemas `core` + `mart`). Machine-readable plan: [units.yml](units.yml). Goldens: `/Volumes/daiwt_03_mig_prod/landing/golden/` (drop `D0`, anchor `2025-12-31`).

**29 units**: 10 silver, 19 gold; 48 golden outputs.

## Dependency graph

```mermaid
flowchart LR
  subgraph silver
    silver_customers
    silver_stores
    silver_products
    silver_orders
    silver_order_items
    silver_payments
    silver_returns
    silver_shipments
    silver_web_events
    silver_campaign_touches
  end
  subgraph gold
    daily_revenue
    customer_ltv
    geo_rollup
    churn_flags
    product_perf
    store_weekly
    category_mix
    basket_affinity
    sessionization
    shipping_sla
    rfm_segments
    promo_lift
    payment_mix
    returns_rate
    attribution
    inventory_snapshot
    finance_export
    cohort_retention
    orchestration
  end
  silver_order_items --> daily_revenue
  silver_orders --> daily_revenue
  silver_customers --> customer_ltv
  silver_order_items --> customer_ltv
  silver_orders --> customer_ltv
  silver_order_items --> geo_rollup
  silver_orders --> geo_rollup
  silver_stores --> geo_rollup
  silver_customers --> churn_flags
  silver_orders --> churn_flags
  silver_order_items --> product_perf
  silver_orders --> product_perf
  silver_products --> product_perf
  silver_stores --> product_perf
  silver_order_items --> store_weekly
  silver_orders --> store_weekly
  silver_stores --> store_weekly
  silver_order_items --> category_mix
  silver_products --> category_mix
  silver_order_items --> basket_affinity
  silver_products --> basket_affinity
  silver_web_events --> sessionization
  silver_shipments --> shipping_sla
  silver_customers --> rfm_segments
  silver_order_items --> rfm_segments
  silver_orders --> rfm_segments
  silver_order_items --> promo_lift
  silver_orders --> promo_lift
  silver_payments --> payment_mix
  silver_order_items --> returns_rate
  silver_products --> returns_rate
  silver_returns --> returns_rate
  silver_campaign_touches --> attribution
  silver_order_items --> inventory_snapshot
  silver_products --> inventory_snapshot
  silver_order_items --> finance_export
  silver_orders --> finance_export
  silver_orders --> cohort_retention
  customer_ltv --> orchestration
  daily_revenue --> orchestration
  returns_rate --> orchestration
  shipping_sla --> orchestration
```

Build order: silver (10, independent) -> gold marts (18, depend only on silver) -> `orchestration` (reads gold `daily_revenue`, `customer_ltv`, `returns_rate`, `shipping_sla`).

## Legacy job -> unit -> targets -> goldens

| Legacy job | Legacy sources | Unit | Layer | Target tables | Golden files | Upstream |
|---|---|---|---|---|---|---|
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql`<br>`legacy/redshift/00_foundation/03_udfs.sql` | `silver_customers` | silver | `silver.customers` | `outputs/D0/foundation/customers.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_stores` | silver | `silver.stores` | `outputs/D0/foundation/stores.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_products` | silver | `silver.products` | `outputs/D0/foundation/products.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_orders` | silver | `silver.orders` | `outputs/D0/foundation/orders.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_order_items` | silver | `silver.order_items` | `outputs/D0/foundation/order_items.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_payments` | silver | `silver.payments` | `outputs/D0/foundation/payments.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_returns` | silver | `silver.returns` | `outputs/D0/foundation/returns.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_shipments` | silver | `silver.shipments` | `outputs/D0/foundation/shipments.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_web_events` | silver | `silver.web_events` | `outputs/D0/foundation/web_events.csv` | bronze |
| foundation (load_core) | `legacy/redshift/00_foundation/02_core_tables.sql` | `silver_campaign_touches` | silver | `silver.campaign_touches` | `outputs/D0/foundation/campaign_touches.csv` | bronze |
| daily_revenue | `legacy/redshift/units/daily_revenue/etl.sql`<br>`legacy/redshift/units/daily_revenue/report.sql` | `daily_revenue` | gold | `gold.daily_revenue`<br>`gold.report_daily_revenue` | `outputs/D0/daily_revenue/daily_revenue.csv`<br>`outputs/D0/daily_revenue/report.csv` | `silver_order_items`, `silver_orders` |
| customer_ltv | `legacy/redshift/units/customer_ltv/etl.sql`<br>`legacy/redshift/units/customer_ltv/report.sql` | `customer_ltv` | gold | `gold.customer_ltv`<br>`gold.report_customer_ltv` | `outputs/D0/customer_ltv/customer_ltv.csv`<br>`outputs/D0/customer_ltv/report.csv` | `silver_customers`, `silver_order_items`, `silver_orders` |
| geo_rollup | `legacy/redshift/units/geo_rollup/etl.sql`<br>`legacy/redshift/units/geo_rollup/report.sql` | `geo_rollup` | gold | `gold.geo_rollup`<br>`gold.report_geo_rollup` | `outputs/D0/geo_rollup/geo_rollup.csv`<br>`outputs/D0/geo_rollup/report.csv` | `silver_order_items`, `silver_orders`, `silver_stores` |
| churn_flags | `legacy/redshift/units/churn_flags/etl.sql`<br>`legacy/redshift/units/churn_flags/report.sql` | `churn_flags` | gold | `gold.churn_flags`<br>`gold.report_churn_flags` | `outputs/D0/churn_flags/churn_flags.csv`<br>`outputs/D0/churn_flags/report.csv` | `silver_customers`, `silver_orders` |
| product_perf | `legacy/redshift/units/product_perf/etl.sql`<br>`legacy/redshift/units/product_perf/report.sql` | `product_perf` | gold | `gold.product_perf`<br>`gold.report_product_perf` | `outputs/D0/product_perf/product_perf.csv`<br>`outputs/D0/product_perf/report.csv` | `silver_order_items`, `silver_orders`, `silver_products`, `silver_stores` |
| store_weekly | `legacy/redshift/units/store_weekly/etl.sql`<br>`legacy/redshift/units/store_weekly/report.sql` | `store_weekly` | gold | `gold.store_weekly`<br>`gold.report_store_weekly` | `outputs/D0/store_weekly/store_weekly.csv`<br>`outputs/D0/store_weekly/report.csv` | `silver_order_items`, `silver_orders`, `silver_stores` |
| category_mix | `legacy/redshift/units/category_mix/etl.sql`<br>`legacy/redshift/units/category_mix/report.sql` | `category_mix` | gold | `gold.category_mix`<br>`gold.report_category_mix` | `outputs/D0/category_mix/category_mix.csv`<br>`outputs/D0/category_mix/report.csv` | `silver_order_items`, `silver_products` |
| basket_affinity | `legacy/redshift/units/basket_affinity/etl.sql`<br>`legacy/redshift/units/basket_affinity/report.sql` | `basket_affinity` | gold | `gold.basket_affinity`<br>`gold.report_basket_affinity` | `outputs/D0/basket_affinity/basket_affinity.csv`<br>`outputs/D0/basket_affinity/report.csv` | `silver_order_items`, `silver_products` |
| sessionization | `legacy/redshift/units/sessionization/etl.sql`<br>`legacy/redshift/units/sessionization/report.sql` | `sessionization` | gold | `gold.web_sessions`<br>`gold.report_sessionization` | `outputs/D0/sessionization/web_sessions.csv`<br>`outputs/D0/sessionization/report.csv` | `silver_web_events` |
| shipping_sla | `legacy/redshift/units/shipping_sla/etl.sql`<br>`legacy/redshift/units/shipping_sla/report.sql` | `shipping_sla` | gold | `gold.shipping_sla`<br>`gold.report_shipping_sla` | `outputs/D0/shipping_sla/shipping_sla.csv`<br>`outputs/D0/shipping_sla/report.csv` | `silver_shipments` |
| rfm_segments | `legacy/redshift/units/rfm_segments/etl.sql`<br>`legacy/redshift/units/rfm_segments/report.sql` | `rfm_segments` | gold | `gold.rfm_segments`<br>`gold.report_rfm_segments` | `outputs/D0/rfm_segments/rfm_segments.csv`<br>`outputs/D0/rfm_segments/report.csv` | `silver_customers`, `silver_order_items`, `silver_orders` |
| promo_lift | `legacy/redshift/units/promo_lift/etl.sql`<br>`legacy/redshift/units/promo_lift/report.sql` | `promo_lift` | gold | `gold.promo_lift`<br>`gold.report_promo_lift` | `outputs/D0/promo_lift/promo_lift.csv`<br>`outputs/D0/promo_lift/report.csv` | `silver_order_items`, `silver_orders` |
| payment_mix | `legacy/redshift/units/payment_mix/etl.sql`<br>`legacy/redshift/units/payment_mix/report.sql` | `payment_mix` | gold | `gold.payment_mix`<br>`gold.report_payment_mix` | `outputs/D0/payment_mix/payment_mix.csv`<br>`outputs/D0/payment_mix/report.csv` | `silver_payments` |
| returns_rate | `legacy/redshift/units/returns_rate/etl.sql`<br>`legacy/redshift/units/returns_rate/report.sql` | `returns_rate` | gold | `gold.returns_rate`<br>`gold.report_returns_rate` | `outputs/D0/returns_rate/returns_rate.csv`<br>`outputs/D0/returns_rate/report.csv` | `silver_order_items`, `silver_products`, `silver_returns` |
| attribution | `legacy/redshift/units/attribution/etl.sql`<br>`legacy/redshift/units/attribution/report.sql` | `attribution` | gold | `gold.attribution`<br>`gold.report_attribution` | `outputs/D0/attribution/attribution.csv`<br>`outputs/D0/attribution/report.csv` | `silver_campaign_touches` |
| inventory_snapshot | `legacy/redshift/units/inventory_snapshot/etl.sql`<br>`legacy/redshift/units/inventory_snapshot/report.sql` | `inventory_snapshot` | gold | `gold.inventory_snapshot`<br>`gold.report_inventory_snapshot` | `outputs/D0/inventory_snapshot/inventory_snapshot.csv`<br>`outputs/D0/inventory_snapshot/report.csv` | `silver_order_items`, `silver_products` |
| finance_export | `legacy/redshift/units/finance_export/etl.sql`<br>`legacy/redshift/units/finance_export/report.sql` | `finance_export` | gold | `gold.finance_monthly`<br>`gold.report_finance_export` | `outputs/D0/finance_export/finance_monthly.csv`<br>`outputs/D0/finance_export/report.csv` | `silver_order_items`, `silver_orders` |
| cohort_retention | `legacy/redshift/units/cohort_retention/etl.sql`<br>`legacy/redshift/units/cohort_retention/report.sql` | `cohort_retention` | gold | `gold.cohort_retention`<br>`gold.report_cohort_retention` | `outputs/D0/cohort_retention/cohort_retention.csv`<br>`outputs/D0/cohort_retention/report.csv` | `silver_orders` |
| orchestration | `legacy/redshift/99_orchestration/exec_summary/etl.sql`<br>`legacy/redshift/99_orchestration/exec_summary/report.sql` | `orchestration` | gold | `gold.exec_summary`<br>`gold.report_orchestration` | `outputs/D0/orchestration/exec_summary.csv`<br>`outputs/D0/orchestration/report.csv` | `customer_ltv`, `daily_revenue`, `returns_rate`, `shipping_sla` |

## Out of scope (no golden output)

- `legacy/redshift/units/finance_export/export.sql`: UNLOAD to placeholder S3/IAM, not run by the legacy build.
- `legacy/redshift/99_orchestration/refresh_schedule.yaml`: scheduler spec, not installed; maps to the Databricks job DAG, not a unit.
- `legacy/redshift/00_foundation/01_schemas.sql`: creates source schemas only.
