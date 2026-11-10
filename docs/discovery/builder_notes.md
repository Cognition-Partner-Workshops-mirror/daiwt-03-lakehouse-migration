# Builder notes by wave

Derived from [business rules](business_rules.md); source pointers below were checked against the local legacy SQL. All paths are relative to `daiwt-03-redshift/legacy/redshift/`. These are semantics to mirror, not changes to business calculations. Analyst golden/engine observations are documented in the catalogue; live engines were not exercised for this handover.

## Wave 0 — Foundation / Platform

- `00_foundation/02_core_tables.sql:2-107`: preserve logical types, nulls, and keys; physical DISTKEY, SORTKEY, DISTSTYLE and ENCODE do not become business transformations. Bronze retains landed values; silver is the typed D0 copy.
- `00_foundation/02_core_tables.sql:8,18`: emit CHAR(4) regions with blank padding (`rpad` to four characters), including downstream direct selections and groupings. Do not globally trim strings.
- `00_foundation/02_core_tables.sql:43,66,76,85-86,94`: wall-clock timestamps map to TIMESTAMP_NTZ; golden-facing rendering is `yyyy-MM-dd HH:mm:ss`, without an offset or fractions. Preserve nulls.
- `00_foundation/02_core_tables.sql:104`: retain SUPER payload as verbatim JSON text in silver; parse only at the attribution read. Preserve JSON key order and whitespace at publication.
- `00_foundation/03_udfs.sql:4-9`: fiscal-quarter expression uses integer division: Jan/Feb/Dec Q4, Mar–May Q1, Jun–Aug Q2, Sep–Nov Q3. Mirror the expression at line 8.
- `00_foundation/03_udfs.sql:12-17`: phone regex strips non-digits, retaining country-code digits; NULL stays NULL. Apply in customer_ltv, not silver.
- Shared arithmetic: integer division and integer AVG truncate toward zero; numeric AVG truncates at input scale. For non-negative decimal aggregates, explicit truncation/floor at the required scale is appropriate. Keep decimal interpolation and division in DECIMAL, not DOUBLE; preserve each intermediate scale before multiplying. Float-to-decimal conversion is not a substitute for decimal truncation; category_mix alone publishes a float ratio (see below).

### Shared expression references

Use the canonical templates in [shared macros §4](shared_macros.md#4-shared-inline-macros-redshift-idioms); M numbers below identify rows there. The proposed `src/sql/shared/macros.sql` is a reference catalogue, not an executable resource. Foundation owns suffix-scoped SQL UDFs as described in [§3](shared_macros.md#3-legacy-udfs--shared-sql-functions); parameterize qualified names and preserve foundation dependencies for callers. Shared-library changes select all registered units.

| Builder | Shared templates |
|---|---|
| Foundation / silver | M1 CHAR padding; M13 date extraction; M15 fiscal quarter; §3 phone UDF; keep SUPER JSON verbatim before M21 consumers. |
| daily_revenue | M13, M18 date/month and decimal line revenue. |
| customer_ltv | M1, M4, M18 and §3.2 phone cleaning. |
| geo_rollup | M1, M18 padded grouping and exact revenue. |
| churn_flags | M3, M12, M19 integer AVG, date subtraction, anchor. |
| product_perf | M1, M2, M18, M20 ordered trimmed LISTAGG and ranking. |
| store_weekly | M1, M10, M13, M18 week boundaries and padded report region. |
| category_mix | M7, M18 decimal quotient converted to DOUBLE. |
| basket_affinity | Plain self-join/HAVING and deterministic report LIMIT; no additional macro. |
| sessionization | M9, M20 second boundaries and explicit window ordering. |
| shipping_sla | M3, M9, M16 integer AVG, hour boundaries and timezone conversion. |
| rfm_segments | M3, M12, M18–M20 integer AVG, recency, revenue, anchor and NULL ordering. |
| promo_lift | M8, M18 decimal interpolation and line revenue. |
| payment_mix | M6, M17 scaled division and NULL-aware conditional functions. |
| returns_rate | M5, M6 integer and scale-15 decimal division. |
| attribution | M21 inner SUPER unnest. |
| inventory_snapshot | M19 literal snapshot anchor; procedure staging semantics remain unit-specific. |
| finance_export | M5, M13–M15, M18 integer fiscal expression and monthly revenue. |
| cohort_retention | M11, M13, M22 month boundaries and decimal HALF_UP rounding. |
| orchestration | M4, M6, M19 scaled aggregates and fixed anchor. |

M3 uses `NULLIF(COUNT(x), 0)` to preserve all-null AVG as NULL. M6 floor templates apply to non-negative values; integer truncation remains toward zero. M17 DECODE matches NULL to NULL; a CASE rewrite must retain that behavior. Analyst M7 uses a decimal quotient followed by DOUBLE conversion for exact D0 rendering; a direct DOUBLE quotient is within documented float tolerance but can differ in the last ULP. Analyst engine checks are retained evidence, not newly executed here.

### Silver — ten entity builders

| Entity | Source pointer | Semantics to mirror |
|---|---|---|
| customers | `00_foundation/02_core_tables.sql:2-14` | BIGINT id, padded region, raw nullable phone, DATE signup and BOOLEAN is_business. |
| stores | `00_foundation/02_core_tables.sql:16-24` | INT id, padded region, state and city strings; no cleansing. |
| products | `00_foundation/02_core_tables.sql:26-37` | NUMERIC(12,2) price/cost and BOOLEAN active; retain all products. |
| orders | `00_foundation/02_core_tables.sql:39-48` | BIGINT order/customer ids, INT store id, NTZ timestamp; retain every status. |
| order_items | `00_foundation/02_core_tables.sql:50-59` | INT quantity and DECIMAL(12,2) unit_price/discount; line net is quantity times net unit price. |
| payments | `00_foundation/02_core_tables.sql:61-69` | Nullable method stays NULL here, scale-2 amount and NTZ paid_ts. |
| returns | `00_foundation/02_core_tables.sql:71-79` | INT quantity, nullable reason and NTZ returned_ts; retain item-level cardinality. |
| shipments | `00_foundation/02_core_tables.sql:81-89` | Keep ship/delivery timestamps as supplied, including null delivery and negative intervals; shipping_sla consumes them directly. |
| web_events | `00_foundation/02_core_tables.sql:91-99` | Preserve nullable customer_id and NTZ event_ts; sessionization applies its own customer filter. |
| campaign_touches | `00_foundation/02_core_tables.sql:101-107` | BIGINT ids, verbatim SUPER JSON text; no explode in silver. |

## Wave 1a — Gold (five units)

### daily_revenue
- `units/daily_revenue/etl.sql:7-13`: truncate timestamps to DATE, count distinct orders per day/channel, sum exact scale-2 line net; inner joins and all statuses remain.
- `units/daily_revenue/report.sql:2-8`: month-start DATE aggregation; sum day-level order counts and revenue.

### customer_ltv
- `units/customer_ltv/etl.sql:10-18`: preserve padded region and regex phone; customer-led LEFT JOINs retain customers without orders. LTV coalesces to zero; AOV remains NULL without item rows.
- `units/customer_ltv/etl.sql:14`: AOV is average net unit price over item rows, not order totals or quantity-weighted price; numeric AVG truncates to scale 2.
- `units/customer_ltv/report.sql:2-9`: group on padded region; truncate AVG(ltv) at scale 2.

### geo_rollup
- `units/geo_rollup/etl.sql:5-17`: mirror explicit GROUPING CASE ids and GROUPING SETS, not an engine-generated grouping id. LEFT JOINs retain stores; region padding survives; rolled-up columns stay NULL. Composite keys must match NULL as a value.

### churn_flags
- `units/churn_flags/etl.sql:13-53`: plpgsql procedure uses a temporary last-order table and per-customer loop. A set-based rewrite must retain all customers, MAX(order_ts)::DATE, and no cross-row state.
- `units/churn_flags/etl.sql:37-45`: literal anchor `2025-12-31`, integer date subtraction, NULL last-order branch, strict >180 and >90 thresholds.
- `units/churn_flags/report.sql:2-7`: integer AVG truncates toward zero; all-null average remains NULL.

### product_perf
- `units/product_perf/etl.sql:7-26`: region-level sales, ROW_NUMBER ordered by units DESC then region ASC, retain top three. LISTAGG uses that same order and removes CHAR trailing padding within concatenated values only.
- `units/product_perf/etl.sql:28-42`: BIGINT units and NUMERIC(18,2) revenue; product-led LEFT JOINs and zero coalescing. Regional calculation joins stores/orders; total-sales calculation reads items directly.

## Wave 1b — Gold (thirteen units)

### store_weekly
- `units/store_weekly/etl.sql:8-16`: Monday week start, plus six days for week end; DATEDIFF week counts Monday boundaries from `2025-01-01`, not whole elapsed seven-day periods.
- `units/store_weekly/report.sql:3-9`: padded store region and boundary week span plus one, retaining the stores join.

### category_mix
- `units/category_mix/etl.sql:7-14`: RATIO_TO_REPORT returns float8; use shared M7's decimal quotient followed by DOUBLE conversion, returning NULL for zero total. Keep revenue itself decimal; publish the share as DOUBLE.

### basket_affinity
- `units/basket_affinity/etl.sql:7-11`: self-join same order with product b > product a, distinct order count, HAVING count >=5.
- `units/basket_affinity/report.sql:4-10`: two product-name joins, concatenation, descending pair count then ascending product ids, LIMIT 50; preserve this total ordering.

### sessionization
- `units/sessionization/etl.sql:12-31`: LAG ordered by event_ts/event_id, strict second-boundary gap >1800, first event starts a session, filter NULL customer ids, running SUM with ROWS UNBOUNDED PRECEDING.
- `units/sessionization/etl.sql:34-42` and `units/sessionization/report.sql:2-8`: NTZ session endpoints; report checkout_sessions sums checkout events rather than counting sessions containing checkout.

### shipping_sla
- `units/shipping_sla/etl.sql:7-12`: COUNT(delivered_ts) excludes NULL; undelivered CASE contributes zero. DATEDIFF hour counts crossed hour boundaries, including negative intervals. Compute the difference of date-hour indices, not elapsed whole hours. Integer AVG truncates toward zero before NUMERIC(10,2) conversion; MAX and <=96 use the same boundary counts.
- `units/shipping_sla/etl.sql:13-14`: CONVERT_TIMEZONE from UTC to America/Los_Angeles is DST-aware over NTZ values; take minimum local delivery hour. Report intentionally selects only its listed metrics (`units/shipping_sla/report.sql:2-5`).

### rfm_segments
- `units/rfm_segments/etl.sql:10-12,23-25`: anchor recency to `2025-12-31`; LEFT JOIN yields NULL recency but zero frequency/monetary without orders. NTILE recency ASC NULLS LAST; frequency/monetary DESC NULLS FIRST; customer_id resolves ties.
- `units/rfm_segments/etl.sql:35` and `units/rfm_segments/report.sql:5`: concatenate three tile digits; report integer AVG frequency truncates.

### promo_lift
- `units/promo_lift/etl.sql:4-15`: decimal per-order totals; MEDIAN and PERCENTILE_CONT(0.9) linearly interpolate non-null values and truncate to input scale 2. Use decimal ranked endpoints and decimal position arithmetic rather than a DOUBLE percentile followed by rounding. Count orders per channel.

### payment_mix
- `units/payment_mix/etl.sql:4-16`: group by raw nullable method; NVL publishes unknown, DECODE chooses family and NVL2 chooses captured/missing. Preserve scale-2 SUM amounts; truncate amount share division to scale 4 rather than round. Retain NULL input grouping separately from its display value.

### returns_rate
- `units/returns_rate/etl.sql:6-13`: BIGINT sold/returned sums, LEFT JOIN by order_item_id, coalesce missing return quantities. Integer return_rate_int truncates; decimal operands NUMERIC(14,4) divide with scale-15 truncation before multiplying by 100. Keep both calculations independently.

### attribution
- `units/attribution/etl.sql:4-9`: SUPER touches navigation is inner array unnest (explode, not explode_outer). Cast campaign/channel to strings, count touches and distinct customer ids per campaign/channel.
- `units/attribution/report.sql:2-7`: sum per-channel customers_reached; do not recount distinct customers across channels.

### inventory_snapshot
- `units/inventory_snapshot/etl.sql:3-41`: plpgsql temporary staging, DELETE by staged product ids, INSERT all products via LEFT JOIN, then drop staging; table starts empty on every run. A full replacement can mirror this D0 execution; do not introduce retained incremental state.
- `units/inventory_snapshot/etl.sql:29-35,41`: fixed snapshot date, zero coalescing and GREATEST(500-units,0)::INT clamp. `units/inventory_snapshot/report.sql:4-5`: on_hand ascending then product_id, LIMIT 50.

### finance_export
- `units/finance_export/etl.sql:5-15`: month-start DATE; fiscal year starts February, fiscal quarter mirrors the UDF's integer expression (not an independently derived fiscal calendar); group by all three expressions.
- `units/finance_export/report.sql:2-7`: aggregate by fiscal year/quarter; February and December can share Q4 within a fiscal year.
- `units/finance_export/export.sql:3-8`: UNLOAD ordered by month, PARALLEL OFF CSV HEADER; target export is one ordered CSV with header in a governed volume. No export golden is defined.

### cohort_retention
- `units/cohort_retention/etl.sql:11-40`: session-scoped temporary cohorts and activity, first order month, distinct active customers, cohort-size join, cleanup. Month DATEDIFF counts calendar boundaries; use year/month indices rather than elapsed days. Emit observed activity only, without filling missing offsets.
- `units/cohort_retention/report.sql:6`: ROUND(100.0*active_buyers/cohort_size,2), decimal arithmetic and half-away-from-zero rounding, not integer division or binary-float conversion.

## Wave 2 — Orchestration / governance

- `99_orchestration/exec_summary/etl.sql:5-18`: retain fixed label/date and read the four published marts. Truncate numeric AVG LTV to scale 2; return percentage quotient to scale 15 before times 100; delivered-weighted shipping average uses already-truncated per-carrier values and quotient scale 4. Do not recompute shipping from raw shipments.
- `99_orchestration/refresh_schedule.yaml:3-39`: 02:00 UTC nightly; load_core precedes both waves; summary waits for both complete waves; finance export waits for wave 1b. Data dependencies for the orchestration unit are only daily_revenue, customer_ltv, returns_rate and shipping_sla; scheduler gates are broader.
- Target scheduling translates cron to Quartz `0 0 2 * * ?`; preserve dependency-success gating. Unit jobs and scheduled wrapper are distinct: only 20 contract units enter the registry. Keep dev schedules paused, follow deployment identity and schema ownership conventions, and scope exports to governed storage as described in [orchestration mapping](orchestration_mapping.md).
- `00_foundation/01_schemas.sql:3-4`: core/mart are source schemas, not target deployment resources. This handover performs no source rebuilds or captures; legacy, seed, golden and validation assets remain read-only. External analytics writes are restricted to the approved `daiwt_03` catalog; any source reset requires explicit operator coordination.
