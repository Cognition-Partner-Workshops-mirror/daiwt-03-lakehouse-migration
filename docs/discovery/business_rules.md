# DAIWT-03 Discovery: business rules and Redshift semantics

Scope: every unit in `.migration/units.yaml` (foundation, wave 1a, wave 1b, orchestration) in
`Cognition-Partner-Workshops-mirror/daiwt-03-redshift`. For each rule: the legacy location
(`path:line`), the exact legacy construct, a Databricks SQL form that reproduces it, and the golden
columns it affects. Paths are relative to `legacy/redshift/` unless they start with `golden/`,
`data/` or `.migration/`.

Evidence levels:
- **[golden]**: confirmed by recomputing from `data/seed/csv/*` (byte-identical to `golden/foundation/*`
  except CHAR padding, see F-1) and comparing with the golden CSV.
- **[dbsql]**: Databricks behavior confirmed with a read-only `SELECT` on a serverless SQL warehouse
  in the devin-gtm workspace.
- **[doc]**: from engine documentation, not re-tested.

Parity defaults (`validation/tolerances.yaml:5-9`): `decimal_abs: 0.000001`,
`float_rel/float_abs: 1e-9`, `string_rstrip: false`. A one-cent drift or a missing CHAR pad is a FAIL.
NULL is the literal `\N` in every golden CSV (`validation/compare.py:18`).

Global constants:
- Reporting anchor `2025-12-31` (`AGENTS.md`; hard-coded literals at
  `units/churn_flags/etl.sql:39,42,43`, `units/rfm_segments/etl.sql:10`,
  `units/inventory_snapshot/etl.sql:41`, `99_orchestration/exec_summary/etl.sql:5-6`). The target must
  use the same literal, never `current_date()`.
- Data is a single D0 drop; all timestamps are wall-clock `TIMESTAMP` (no time zone) in Redshift → use
  `TIMESTAMP_NTZ` in Databricks so no session time zone is applied.

---

## Cross-cutting semantics catalogue

| # | Redshift semantic | Databricks default | Reproducing form | Evidence |
|---|---|---|---|---|
| S-1 | `INT / INT` is integer division (truncates toward zero) | `/` returns DOUBLE (`455/8892` = 0.0511…) | `a DIV b` (or `CAST(a/b AS BIGINT)` for non-negative) | [golden][dbsql] |
| S-2 | `AVG(int)` returns an integer, truncated | DOUBLE (`avg(1,2)` = 1.5) | `CAST(TRUNC(AVG(x)) AS BIGINT)`; equivalently `SUM(x) DIV COUNT(x)` for non-negative sums. Note: Redshift truncates toward zero, so for possibly-negative inputs use `CAST(AVG(x) AS BIGINT)` (cast truncates toward zero) | [golden][dbsql] |
| S-3 | `AVG(numeric(p,s))` returns scale `s`, truncated | `DECIMAL(38,s+4)`, rounded (`avg(1.00,2.01)` = 1.505000) | `CAST(FLOOR(AVG(x), s) AS DECIMAL(38,s))` (all affected values are ≥ 0) | [golden][dbsql] |
| S-4 | Numeric division truncates at its result scale | Rounds at the adjusted scale (e.g. `DECIMAL(14,4)/DECIMAL(14,4)*100` → `DECIMAL(37,19)` = 5.11695906432748538) | Floor the quotient at the Redshift scale before further arithmetic, e.g. `CAST(FLOOR(a/b, 15) * 100 AS DECIMAL(38,15))` → `5.116959064327400` | [golden][dbsql] |
| S-5 | `MEDIAN` / `PERCENTILE_CONT` over NUMERIC keep the input scale (2) and truncate; NULLs ignored | Return DOUBLE (`percentile_cont` on DECIMAL(12,2) → `double`) | Interpolate in DECIMAL: `n = COUNT(x)`, `pos = 1 + p*(n-1)`, take rows `FLOOR(pos)` and `CEIL(pos)` from `ROW_NUMBER() OVER (ORDER BY x NULLS LAST)`, `lo + (hi-lo)*(pos-FLOOR(pos))`, then `CAST(FLOOR(v,2) AS DECIMAL(38,2))` | [golden][dbsql] |
| S-6 | `RATIO_TO_REPORT(x)` returns `float8`; NULL when the total is 0 | `x/SUM(x) OVER()` on DECIMAL returns `DECIMAL(38,6)` (0.154113) | `try_divide(CAST(x AS DOUBLE), SUM(CAST(x AS DOUBLE)) OVER ())` | [golden][dbsql] |
| S-7 | `CHAR(n)` is blank-padded and padding is returned to the client (`'NE  '`) | `CHAR(4)` is **not** padded on read (`length(CAST('NE' AS CHAR(4)))` = 2) | Store/emit `rpad(region, 4, ' ')` as STRING | [golden][dbsql] |
| S-8 | `LISTAGG` of a CHAR column drops trailing pad (`…,NE`) | n/a | `array_join(transform(array_sort(collect_list(struct(-units AS k1, rtrim(region) AS k2, rtrim(region) AS v))), x -> x.v), ',')` or `listagg(rtrim(region), ',') WITHIN GROUP (ORDER BY units DESC, region)` (Databricks `listagg` verified) | [golden][dbsql] |
| S-9 | NULL sorts as the largest value: ASC → NULLS LAST, DESC → NULLS FIRST (ORDER BY, window ORDER BY, NTILE, ROW_NUMBER) | ASC → NULLS FIRST, DESC → NULLS LAST (`ntile(2) OVER (ORDER BY x)` puts NULL in tile 1) | Always write the null order explicitly: `ASC NULLS LAST`, `DESC NULLS FIRST` | [golden][dbsql] |
| S-10 | `DATEDIFF(unit, a, b)` counts unit **boundaries** crossed | `timestampdiff`/`datediff(HOUR, …)` count whole elapsed units, truncating toward zero (`2026-01-01 03:00:37 → 2025-12-31 23:59:59`: Databricks −3, Redshift −4) | Hour: `(epoch_wall(date_trunc_hour(b)) - epoch_wall(date_trunc_hour(a))) DIV 3600`, where `epoch_wall(ts) = datediff(CAST(ts AS DATE), DATE'1970-01-01')*86400 + hour(ts)*3600 + minute(ts)*60 + second(ts)` on TIMESTAMP_NTZ (no session TZ). Second: whole-second inputs → `timestampdiff(SECOND,a,b)` is identical. Day on DATE: `datediff(b,a)`. Week: `datediff(date_trunc('WEEK',b), date_trunc('WEEK',a)) DIV 7` (Monday weeks). Month: `(year(b)*12+month(b)) - (year(a)*12+month(a))` | [golden][dbsql] |
| S-11 | `DATE - DATE` returns INTEGER days | Returns `INTERVAL DAY` | `datediff(b, a)` (INT) | [dbsql] |
| S-12 | `CONVERT_TIMEZONE('UTC','America/Los_Angeles', ts)` on TIMESTAMP (NTZ), DST-aware | `convert_timezone(src, tgt, ts)` exists, returns TIMESTAMP_NTZ, DST-aware (Jul 08:30 → 01:30, Jan 08:30 → 00:30) | `convert_timezone('UTC','America/Los_Angeles', ts)` | [dbsql] |
| S-13 | `DECODE(expr, s1, r1, …, default)`; `NVL`; `NVL2` | Same names exist with same semantics (`decode` matches NULL to NULL, like Redshift) | `decode(...)` / `nvl` / `nvl2`, or explicit `CASE` | [dbsql] |
| S-14 | `GROUPING(col)` returns 0/1 | Same | `grouping(col)` | [dbsql] |
| S-15 | `ROUND(numeric, 2)`: half away from zero | `round` is HALF_UP (same for positives) | `round(x, 2)`; keep the expression in DECIMAL | [golden][dbsql] |
| S-16 | `SUM(int)` returns BIGINT; `COUNT` BIGINT | `SUM(int)` BIGINT | none; cast to BIGINT where the golden type is int8 | [doc] |
| S-17 | `TRUNC(ts)` → DATE; `ts::DATE` | `CAST(ts AS DATE)` | `CAST(ts AS DATE)`; `DATE_TRUNC('month', ts)::DATE` → `CAST(date_trunc('MONTH', ts) AS DATE)` | [dbsql] |
| S-18 | SUPER navigation `FROM t, t.payload.touches tc` (PartiQL unnest, inner: rows with empty/missing arrays vanish) | n/a | `LATERAL VIEW explode(from_json(payload, 'STRUCT<touches: ARRAY<STRUCT<channel: STRING, campaign_id: STRING, ts: STRING>>>').touches) e AS tc` (explode, not explode_outer) | [golden][dbsql] |
| S-19 | Physical DDL (`DISTKEY`, `SORTKEY`, `DISTSTYLE`, `ENCODE`) | No semantic effect | Drop; optional `CLUSTER BY` | [doc] |
| S-20 | Golden CSV row order is not significant: comparison is keyed (`validation/compare.py:106-150`) | | `ORDER BY`/`SORTKEY` only matter where they feed `LIMIT`, `ROW_NUMBER`, `NTILE`, `LISTAGG` or a running `SUM` | [golden] |

---

## Wave 0: Foundation / Platform

### F-1 CHAR(4) region padding (silver.customers, silver.stores)
- Legacy: `00_foundation/02_core_tables.sql:8` (`region CHAR(4) ENCODE lzo`) and `:18` (stores).
- Seed values `NE`, `SW` (`data/seed/generate_seed.py:26`, written unpadded); goldens hold `'NE  '`
  (174 customers) and `'SW  '` (157 customers); stores `'NE  '` ×4, `'SW  '` ×4 [golden]. These are the only
  differences between `data/seed/csv/{customers,stores}.csv` and `golden/foundation/` (all other eight
  tables are byte-identical row sets).
- Databricks: `rpad(region, 4, ' ') AS region` (STRING) in silver. Do not rely on `CHAR(4)` (S-7).
- Contract types: `region: bpchar` in `silver.customers`, `silver.stores`, `gold.customer_ltv`,
  `gold.report_customer_ltv`, `gold.geo_rollup(.report)`, `gold.report_store_weekly`.
- Downstream: every gold column that selects `region` directly inherits the pad (customer_ltv.region,
  report_customer_ltv.region, geo_rollup.region, report_store_weekly.region); LISTAGG drops it (P-5).

### F-2 Type mapping (all silver tables)
- Legacy: `00_foundation/02_core_tables.sql:2-107`.
- `BIGINT`→BIGINT, `INT`→INT, `NUMERIC(12,2)`→`DECIMAL(12,2)`, `VARCHAR(n)`→STRING, `BOOLEAN`→BOOLEAN
  (golden renders `true`/`false`), `DATE`→DATE, `TIMESTAMP`→`TIMESTAMP_NTZ` (golden renders
  `YYYY-MM-DD HH:MM:SS`, no fraction, no offset), `SUPER`→STRING (F-3).
- Drop `DISTKEY/SORTKEY/DISTSTYLE/ENCODE` (S-19). `NOT NULL` on the ids may be kept.
- NULLs present in seed: `customers.phone` 181, `payments.method` 2826, `shipments.delivered_ts` 987,
  `web_events.customer_id` 3707, `returns.reason` 461 [golden].

### F-3 SUPER payload (silver.campaign_touches)
- Legacy: `00_foundation/02_core_tables.sql:104` (`payload SUPER`).
- Golden `golden/foundation/campaign_touches.csv` payload text is byte-identical to the seed JSON
  (compact `separators=(",", ":")`, key order `customer_ref, touches, meta`) [golden].
- Databricks: keep `payload` as STRING exactly as landed. Re-serializing via VARIANT/`to_json` risks
  key order or spacing changes. Parse at read time (S-18).
- Shape (all 8000 rows): top keys `{customer_ref, touches, meta}`; every touch has
  `{channel, campaign_id, ts}`; 20003 touches total; `customer_ref` always equals `customer_id` [golden].

### F-4 UDF `f_fiscal_qtr(d DATE) RETURNS VARCHAR(8)`
- Legacy: `00_foundation/03_udfs.sql:4-9`
  `SELECT 'Q' || ((((EXTRACT(MONTH FROM $1)::INT + 9) % 12) / 3) + 1)::VARCHAR`.
- `/` is integer division (S-1). Resulting mapping (what the goldens carry, `golden/finance_export/finance_monthly.csv`):
  Jan Q4, Feb Q4, Mar–May Q1, Jun–Aug Q2, Sep–Nov Q3, Dec Q4 [golden][dbsql].
- Databricks (SQL UDF or inline):
  `concat('Q', CAST((((month(d) + 9) % 12) DIV 3) + 1 AS STRING))`. The target must reproduce this mapping
  exactly, using the expression at `03_udfs.sql:8`.
- Affects: `gold.finance_monthly.fiscal_qtr`, `gold.report_finance_export.fiscal_qtr` and its grouping
  (`2025 Q4` = Feb + Dec 2025: 3198 orders, 1706085.34).

### F-5 UDF `f_clean_phone(p VARCHAR) RETURNS VARCHAR(32)`
- Legacy: `00_foundation/03_udfs.sql:12-17` `SELECT REGEXP_REPLACE($1, '[^0-9]', '')`.
- Removes every non-digit, including a leading `+1` country code's `+` (the `1` stays). NULL in → NULL out.
  Golden: 987 ten-digit and 332 eleven-digit values (`+1 (…)` style keeps the `1`), 181 NULL [golden].
- Databricks: `regexp_replace(p, '[^0-9]', '')` (identical incl. NULL) [dbsql].
- Affects: `gold.customer_ltv.clean_phone`.

---

## Silver per entity

Silver is a 1:1 typed copy of `core.*` for D0 (the legacy has no cleansing layer;
`00_foundation/02_core_tables.sql:1` "append-only raw extract"). Rules per entity:

| silver table | keys | rules |
|---|---|---|
| customers | customer_id | F-1 rpad region; F-2 types; phone left raw (cleaning happens in customer_ltv) |
| stores | store_id | F-1 rpad region |
| products | product_id | `unit_price`, `cost` DECIMAL(12,2); `active` BOOLEAN |
| orders | order_id | `order_ts` TIMESTAMP_NTZ; `status` ∈ {complete, returned, cancelled} kept as-is (no unit filters on it) |
| order_items | order_item_id | `unit_price`, `discount` DECIMAL(12,2); line net = `quantity * (unit_price - discount)` (DECIMAL(…,2), exact) |
| payments | payment_id | `method` NULL in 2826 rows, kept NULL in silver (NVL happens in payment_mix) |
| returns | return_id | at most one return per order_item_id in D0 (0 duplicates) [golden] |
| shipments | shipment_id | `delivered_ts` NULL = in flight; 59 rows have `delivered_ts < ship_ts` and 63 rows have `ship_ts` after the anchor; kept as-is (they feed shipping_sla through DATEDIFF, see G-shipping_sla) |
| web_events | event_id | 3707 rows with NULL customer_id kept (filtered in sessionization) |
| campaign_touches | touch_id | payload STRING verbatim (F-3) |

---

## Wave 1a: Gold per unit

### daily_revenue: `gold.daily_revenue`, `gold.report_daily_revenue`
- `units/daily_revenue/etl.sql:7` `TRUNC(o.order_ts)::DATE AS order_date` → `CAST(order_ts AS DATE)` (S-17).
- `:9` `COUNT(DISTINCT o.order_id)`; `:10` `SUM(oi.quantity * (oi.unit_price - oi.discount))`: exact DECIMAL scale 2.
- `:11-12` inner JOIN orders↔order_items; all statuses included.
- `report.sql:2` `DATE_TRUNC('month', order_date)::DATE` → `CAST(date_trunc('MONTH', order_date) AS DATE)`.
- Golden: 1460 day×channel rows; revenue total 10543825.25 [golden].

### customer_ltv: `gold.customer_ltv`, `gold.report_customer_ltv`
- `units/customer_ltv/etl.sql:10` `c.region` → padded (F-1). Golden `NE  `, `SW  `.
- `:11` `f_clean_phone(c.phone)` (F-5).
- `:12` `COUNT(DISTINCT o.order_id)`; 146 customers without orders → 0.
- `:13` `COALESCE(SUM(oi.quantity * (oi.unit_price - oi.discount)), 0)` → `ltv`; customers without orders = `0.00` (scale 2, e.g. customer 1019) [golden].
- `:14` `AVG(oi.unit_price - oi.discount) AS aov`: average of line net **unit** price over order-item rows
  (not quantity-weighted, not per order); NULL for the 146 customers without orders; truncated to scale 2
  (S-3). Recomputed: truncation matches all 1354 rows; rounding would differ on 669 rows [golden].
  Databricks: `CAST(FLOOR(AVG(oi.unit_price - oi.discount), 2) AS DECIMAL(38,2))`.
- `:15-17` customers LEFT JOIN orders LEFT JOIN order_items; `:18` GROUP BY customer_id, region, phone.
- `report.sql:2-8`: group by padded `region` (6 groups); `AVG(ltv)` truncated at scale 2 (S-3), e.g.
  `NE  ` 7118.1464… → `7118.14`, EAST 6935.9107… → `6935.91` [golden].
  Databricks: `CAST(FLOOR(AVG(ltv), 2) AS DECIMAL(38,2))`.

### geo_rollup: `gold.geo_rollup`, `gold.report_geo_rollup`
- `units/geo_rollup/etl.sql:5-9`
  `CASE WHEN GROUPING(s.region)=0 AND GROUPING(s.state)=1 THEN 1 WHEN GROUPING(s.region)=1 AND GROUPING(s.state)=0 THEN 2 ELSE 3 END`
  → same in Databricks (S-14).
- `:17` `GROUP BY GROUPING SETS ((s.region), (s.state), ())` → identical syntax.
- `:10` region padded (F-1): golden grouping_id 1 rows `NE  `, `SW  `; non-grouped columns are NULL (`\N`).
- `:12` `COUNT(DISTINCT o.order_id)`; `:13` `COALESCE(SUM(...),0)`; `:14-16` stores LEFT JOIN orders LEFT JOIN items.
- Golden: 21 rows (6 region, 14 state, 1 total = 20000 / 10543825.25). Keys `[grouping_id, region, state]` include NULLs; the key match must treat NULL as a value.

### churn_flags: `gold.churn_flags`, `gold.report_churn_flags`
- plpgsql: `units/churn_flags/etl.sql:13-51` `CREATE OR REPLACE PROCEDURE sp_build_churn_flags()` with
  `DECLARE rec RECORD`, `CREATE TEMP TABLE tmp_last_orders` (`:18-21`), INSERT…SELECT (`:23-28`),
  `FOR rec IN SELECT … ORDER BY customer_id LOOP INSERT … END LOOP` (`:30-47`), `DROP TABLE` (`:49`),
  `CALL sp_build_churn_flags();` (`:53`).
- The loop is row-at-a-time but each output row depends only on its own input row → set-based equivalent:
  ```sql
  WITH tmp_last_orders AS (
    SELECT c.customer_id, CAST(MAX(o.order_ts) AS DATE) AS last_order_date
    FROM silver.customers c LEFT JOIN silver.orders o ON o.customer_id = c.customer_id
    GROUP BY c.customer_id)
  SELECT customer_id, last_order_date,
         CASE WHEN last_order_date IS NULL THEN NULL
              ELSE datediff(DATE'2025-12-31', last_order_date) END AS days_since_order,
         CASE WHEN last_order_date IS NULL THEN 'never_ordered'
              WHEN datediff(DATE'2025-12-31', last_order_date) > 180 THEN 'churned'
              WHEN datediff(DATE'2025-12-31', last_order_date) > 90  THEN 'at_risk'
              ELSE 'active' END AS churn_flag
  FROM tmp_last_orders
  ```
  (temp table → CTE; `DATE - DATE` → `datediff` (S-11); thresholds strict `>`; CASE order matters.)
- `:25` `MAX(o.order_ts)::DATE`: max timestamp then cast.
- Golden: active 1323, at_risk 30, churned 1, never_ordered 146.
- `report.sql:4` `AVG(days_since_order)` over INT → truncated integer (S-2): active 22.57→`22`,
  at_risk 115.3→`115`, churned `203`, never_ordered `\N` [golden]. Databricks `CAST(AVG(days_since_order) AS BIGINT)`.

### product_perf: `gold.product_perf`, `gold.report_product_perf`
- `units/product_perf/etl.sql:7-15` `per_store` aggregates units per (product_id, **store region**) via
  order_items→orders→stores (inner joins).
- `:16-27` `ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY units DESC, region)`, `rn <= 3`, then
  `LISTAGG(region, ',') WITHIN GROUP (ORDER BY units DESC, region)::VARCHAR(64) AS codes`.
  - LISTAGG output drops CHAR pad: golden `EAST,NRTH,NE` (S-8) [golden].
  - Tie resolution on `region` ascending is significant: 32 products have a tie between rank 3 and 4 [golden].
    Padded vs trimmed order is the same for the six region codes (`EAST < NE < NRTH < SOTH < SW < WEST`).
  - Databricks: `ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY units DESC, region)` then
    `listagg(rtrim(region), ',') WITHIN GROUP (ORDER BY units DESC, region)` (or the
    `array_sort(collect_list(struct(...)))` form). Recomputed list matches all 300 rows [golden].
- `:28-34` `SUM(quantity)::BIGINT`, `SUM(quantity*(unit_price-discount))::NUMERIC(18,2)`.
- `:35-43` products LEFT JOIN agg / top_stores; `COALESCE(...,0)`; top_stores NULL only for products
  with no sales (none in D0).
- `report.sql:2-8` straightforward GROUP BY category.

---

## Wave 1b: Gold per unit

### store_weekly: `gold.store_weekly`, `gold.report_store_weekly`
- `units/store_weekly/etl.sql:8` `DATE_TRUNC('week', o.order_ts)::DATE`: Monday-start week (both engines
  Monday) → `CAST(date_trunc('WEEK', order_ts) AS DATE)`. First week 2024-12-30 [golden][dbsql].
- `:9` `DATEADD(day, 6, DATE_TRUNC('week', o.order_ts))::DATE` → `date_add(CAST(date_trunc('WEEK', order_ts) AS DATE), 6)`.
- `:10-11` `DATEDIFF(week, DATE '2025-01-01', DATE_TRUNC('week', o.order_ts)::DATE)`: week boundaries
  between Wed 2025-01-01 and the week start; week 2024-12-30 → `0`, 2025-01-06 → `1`, max 52 (S-10).
  Databricks `datediff(week_start, CAST(date_trunc('WEEK', DATE'2025-01-01') AS DATE)) DIV 7`.
- `:16` GROUP BY `store_id, DATE_TRUNC('week', o.order_ts)`.
- `report.sql:4` `DATEDIFF(week, MIN(w.week_start), MAX(w.week_start)) + 1` (Monday dates → `datediff DIV 7 + 1`);
  all 40 stores = 53. `report.sql:3` `s.region` padded (F-1).

### category_mix: `gold.category_mix`, `gold.report_category_mix`
- `units/category_mix/etl.sql:7` `RATIO_TO_REPORT(revenue) OVER ()` → float8 (S-6).
  Databricks `try_divide(CAST(revenue AS DOUBLE), SUM(CAST(revenue AS DOUBLE)) OVER ())`.
  Python float recomputation agrees with golden to ≤1 ulp (e.g. `0.15411330152688182` vs `…818`), within
  `float_rel 1e-9` [golden].
- `:10-11` `SUM(quantity)`, `SUM(quantity*(unit_price-discount))`; `:12-14` inner join products; 6 categories.

### basket_affinity: `gold.basket_affinity`, `gold.report_basket_affinity`
- `units/basket_affinity/etl.sql:7-11` self-join `b.product_id > a.product_id` within order,
  `COUNT(DISTINCT a.order_id)`, `HAVING … >= 5`. Golden 50 pairs (48 at 5, 2 at 6).
- `report.sql:4` `pa.product_name || ' + ' || pb.product_name` → `concat_ws(' + ', …)` or `||`
  (both NULL-propagating with `||`; names are non-NULL).
- `report.sql:9-10` `ORDER BY pair_orders DESC, product_id_a, product_id_b LIMIT 50`: deterministic total
  order; the D0 mart has exactly 50 rows so the LIMIT keeps all.

### sessionization: `gold.web_sessions`, `gold.report_sessionization`
- `units/sessionization/etl.sql:12-20` `LAG(event_ts) OVER (PARTITION BY customer_id ORDER BY event_ts, event_id)`;
  new session when LAG IS NULL or `DATEDIFF(second, lag, event_ts) > 1800` (strict).
  Timestamps are whole seconds, so `timestampdiff(SECOND, lag, event_ts)` is identical to boundary counting (S-10).
- `:22` `WHERE customer_id IS NOT NULL` (drops 3707 events).
- `:29-31` `SUM(new_session) OVER (PARTITION BY customer_id ORDER BY event_ts, event_id ROWS UNBOUNDED PRECEDING)`
  → identical; `session_id` starts at 1 per customer. No (customer_id, event_ts) ties in D0, `event_id`
  is the secondary ordering key.
- `:39` `SUM(CASE WHEN event_type='checkout' THEN 1 ELSE 0 END)`.
- Golden 21280 sessions; `report.sql` aggregates per customer (`checkout_sessions` = SUM of checkout_events, not count of sessions).

### shipping_sla: `gold.shipping_sla`, `gold.report_shipping_sla`
- `units/shipping_sla/etl.sql:9` `AVG(DATEDIFF(hour, s.ship_ts, s.delivered_ts))::NUMERIC(10,2)`:
  DATEDIFF returns BIGINT, AVG over integer truncates (S-2), then cast → `71.00` (dhl exact 71.99, fedex
  71.52, ups 71.83, usps 72.18) [golden].
  Databricks: `CAST(CAST(AVG(h) AS BIGINT) AS DECIMAL(10,2))` where `h` is the boundary hour count.
- `:9-12` hour boundary counting (S-10). D0 has 59 shipments with `delivered_ts < ship_ts` (ship_ts after
  2025-12-31 while delivered_ts is 2025-12-31 23:59:59); on those rows Databricks `timestampdiff(HOUR)`
  differs from Redshift by 1 (e.g. shipment 1: Redshift −4, Databricks −3) [golden][dbsql]. Use the
  boundary form:
  ```sql
  (  (datediff(CAST(delivered_ts AS DATE), DATE'1970-01-01')*24 + hour(delivered_ts))
   - (datediff(CAST(ship_ts AS DATE),      DATE'1970-01-01')*24 + hour(ship_ts)) ) AS h
  ```
  Min h per carrier is negative (−44…−66); these rows count toward `on_time_96h` (`<= 96`) and the AVG.
- `:7-8` `COUNT(delivered_ts)`, `COUNT(*) - COUNT(delivered_ts)`; NULL delivered_ts → DATEDIFF NULL →
  excluded from AVG/MAX and from `on_time_96h` (CASE yields 0).
- `:10` `MAX(...)` = 139 for all carriers.
- `:13-14` `MIN(EXTRACT(HOUR FROM CONVERT_TIMEZONE('UTC','America/Los_Angeles', s.delivered_ts)))::INT`
  → `CAST(MIN(hour(convert_timezone('UTC','America/Los_Angeles', delivered_ts))) AS INT)` (S-12). Golden `0` for all carriers.
- Report omits `earliest_local_delivery_hour`.

### rfm_segments: `gold.rfm_segments`, `gold.report_rfm_segments`
- `units/rfm_segments/etl.sql:10` `DATEDIFF(day, MAX(o.order_ts)::DATE, DATE '2025-12-31')` →
  `datediff(DATE'2025-12-31', CAST(MAX(o.order_ts) AS DATE))`; NULL for the 146 customers without orders.
- `:11` `COUNT(DISTINCT o.order_id)` (0, never NULL); `:12` `COALESCE(SUM(...), 0)` (0, never NULL).
- `:23` `NTILE(5) OVER (ORDER BY recency_days ASC, customer_id)`: Redshift places NULL recency **last**
  → all 146 NULL-recency customers get `r_tile = 5` [golden]. Databricks must write
  `ORDER BY recency_days ASC NULLS LAST, customer_id` (S-9; default would put them in tile 1).
- `:24-25` `NTILE(5) OVER (ORDER BY frequency DESC, customer_id)`, `monetary DESC`: no NULLs, ties resolved
  by customer_id; write `DESC NULLS FIRST` anyway for fidelity. Never-ordered customers land in f=5, m=5.
- `:35` `(r_tile::VARCHAR || f_tile::VARCHAR || m_tile::VARCHAR)::VARCHAR(3)` → `concat(r_tile, f_tile, m_tile)`.
- `report.sql:5` `AVG(frequency)` over BIGINT → truncated integer (S-2). `SUM(monetary)` exact.
  Golden 103 segments.

### promo_lift: `gold.promo_lift`, `gold.report_promo_lift`
- `units/promo_lift/etl.sql:4-11` per-order total `SUM(quantity*(unit_price-discount))` (DECIMAL scale 2).
- `:14` `MEDIAN(order_total)` and `:15` `PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY order_total)`:
  linear interpolation, result truncated to scale 2 (S-5). Recomputed exact values vs golden:
  mobile median 390.215→`390.21`, p90 1093.965→`1093.96`; web median 414.445→`414.44`;
  phone p90 1107.372→`1107.37`; store p90 1110.566→`1110.56` [golden]. Rounding or DOUBLE output
  (Databricks default) fails parity on these.
  ```sql
  ranked AS (SELECT sales_channel, order_total,
                    ROW_NUMBER() OVER (PARTITION BY sales_channel ORDER BY order_total NULLS LAST) AS rn,
                    COUNT(order_total) OVER (PARTITION BY sales_channel) AS n FROM order_totals),
  -- for p in (0.5, 0.9): pos = 1 + p*(n-1); lo = row FLOOR(pos), hi = row CEIL(pos)
  -- value = CAST(FLOOR(lo + (hi - lo) * (pos - FLOOR(pos)), 2) AS DECIMAL(38,2))
  ```
- `:13` `COUNT(*)` orders per channel.

### payment_mix: `gold.payment_mix`, `gold.report_payment_mix`
- `units/payment_mix/etl.sql:4` `NVL(p.method, 'unknown')`; `:16` GROUP BY raw `p.method` (NULL group
  becomes `unknown`).
- `:5-10` `DECODE(NVL(p.method,'unknown'), 'card','CARD', 'cash','CASH', 'wallet','DIGITAL', 'gift_card','DIGITAL', 'OTHER')`
  → `decode(...)` or CASE (S-13). `unknown` → `OTHER`.
- `:11` `NVL2(p.method, 'captured', 'missing')` → `nvl2` (S-13).
- `:13` `SUM(p.amount)` exact scale 2.
- `:14` `SUM(p.amount) / SUM(SUM(p.amount)) OVER ()`: NUMERIC/NUMERIC with result scale 4, truncated
  (card 0.427603…→`0.4276`, cash 0.147260…→`0.1472`, unknown 0.137959…→`0.1379`); shares sum to 0.9998 [golden].
  Databricks: `CAST(FLOOR(SUM(p.amount) / SUM(SUM(p.amount)) OVER (), 4) AS DECIMAL(38,4))`
  (the Databricks quotient is `DECIMAL(38,6)` rounded at 6; no D0 value has digits 5–6 near a carry).
- `report.sql:2-7` group by `method_family` (DIGITAL = wallet + gift_card).

### returns_rate: `gold.returns_rate`, `gold.report_returns_rate`
- `units/returns_rate/etl.sql:6-7` `SUM(oi.quantity)::BIGINT`, `COALESCE(SUM(r.quantity),0)::BIGINT`.
- `:8` `COALESCE(SUM(r.quantity), 0) / SUM(oi.quantity)`: integer division (S-1) → `0` for all 6 categories.
  Databricks `COALESCE(SUM(r.quantity),0) DIV SUM(oi.quantity)`.
- `:9-10` `(COALESCE(SUM(r.quantity),0)::NUMERIC(14,4) / SUM(oi.quantity)::NUMERIC(14,4)) * 100`:
  quotient truncated at scale 15, then ×100 keeps scale 15 (S-4). Accessories 455/8892 →
  `5.116959064327400` (exact 5.1169590643274853…) [golden][dbsql].
  Databricks `CAST(FLOOR(CAST(ret AS DECIMAL(14,4)) / CAST(sold AS DECIMAL(14,4)), 15) * 100 AS DECIMAL(38,15))`.
- `:13` `LEFT JOIN core.returns r ON r.order_item_id = oi.order_item_id`: one row per return; D0 has ≤1
  return per item, so no fan-out of `sold_qty`.
- `report.sql:4` `ORDER BY return_pct DESC, category` (no LIMIT).

### attribution: `gold.attribution`, `gold.report_attribution`
- `units/attribution/etl.sql:8` `FROM core.campaign_touches t, t.payload.touches tc`: PartiQL unnest of the
  `touches` array (S-18) → `LATERAL VIEW explode(from_json(payload, 'STRUCT<touches: ARRAY<STRUCT<channel: STRING, campaign_id: STRING, ts: STRING>>>').touches) e AS tc`
  (or `parse_json` + `variant_explode`). Inner semantics: use `explode`, not `explode_outer`.
- `:4-5,9` `tc.campaign_id::VARCHAR(16)`, `tc.channel::VARCHAR(16)` → STRING (values fit).
- `:6` `COUNT(*)` touches (20003 total); `:7` `COUNT(DISTINCT t.customer_id)` per (campaign, channel).
- Golden 100 rows (20 campaigns × 5 channels).
- `report.sql:3-4` `SUM(touches)`, `SUM(customers_reached)` across channels (sum of per-channel distinct
  counts, e.g. CMP-001 `918`); the target must sum the mart column, not recount distinct customers.

### inventory_snapshot: `gold.inventory_snapshot`, `gold.report_inventory_snapshot`
- plpgsql: `units/inventory_snapshot/etl.sql:13-39` `sp_upsert_inventory(p_snapshot DATE)`:
  temp table `stg_inventory` (`:16-24`, `SUM(quantity)::BIGINT` per product), `DELETE … WHERE product_id IN (SELECT …)`
  (`:26-27`), `INSERT … SELECT` from products LEFT JOIN staging (`:29-35`), `DROP` (`:37`),
  `CALL sp_upsert_inventory('2025-12-31'::DATE)` (`:41`). Target table is dropped/recreated empty first (`:3-11`).
- Databricks: SQL scripting block or a single statement; staging as CTE; DELETE+INSERT → `MERGE` or
  `CREATE OR REPLACE` (the table is empty before the CALL, so both yield the same rows):
  ```sql
  BEGIN
    DECLARE p_snapshot DATE DEFAULT DATE'2025-12-31';
    MERGE INTO gold.inventory_snapshot t USING (
      SELECT p.product_id, p_snapshot AS snapshot_date,
             COALESCE(s.units_sold, 0) AS units_sold,
             CAST(GREATEST(500 - COALESCE(s.units_sold, 0), 0) AS INT) AS on_hand
      FROM silver.products p
      LEFT JOIN (SELECT product_id, CAST(SUM(quantity) AS BIGINT) units_sold
                 FROM silver.order_items GROUP BY product_id) s ON s.product_id = p.product_id) src
    ON t.product_id = src.product_id
    WHEN MATCHED THEN UPDATE SET * WHEN NOT MATCHED THEN INSERT *;
  END
  ```
- `:33` `GREATEST(500 - units, 0)::INT`; D0 on_hand range 278…(≥0, clamp never hit).
- `report.sql:4-5` `ORDER BY on_hand ASC, product_id LIMIT 50`: deterministic; the LIMIT matters
  (300 → 50 rows).

### finance_export: `gold.finance_monthly`, `gold.report_finance_export`, export file
- `units/finance_export/etl.sql:5` `DATE_TRUNC('month', o.order_ts)::DATE AS month`.
- `:6-9` fiscal year: `CASE WHEN EXTRACT(MONTH FROM order_ts) >= 2 THEN year ELSE year - 1 END`
  (Feb start) → `CASE WHEN month(order_ts) >= 2 THEN year(order_ts) ELSE year(order_ts) - 1 END`. Jan 2025 → 2024.
- `:10` `f_fiscal_qtr(TRUNC(o.order_ts)::DATE)` (F-4).
- `:15` `GROUP BY 1, 2, 3`; golden 12 months.
- `report.sql:2-7` GROUP BY (fiscal_year, fiscal_qtr): 5 rows `2024 Q4, 2025 Q1, Q2, Q3, Q4`; `2025 Q4`
  combines Feb 2025 (1508 orders) and Dec 2025 (1690) [golden].
- `export.sql:3-8` `UNLOAD ('SELECT * FROM mart.finance_monthly ORDER BY month') TO 's3://…' IAM_ROLE … PARALLEL OFF CSV HEADER`:
  single CSV with header, ordered by month. Listed under `capture_skip` (`.migration/units.yaml`); no golden.
  Databricks: write one CSV with header to a UC volume (e.g. `gold.exports`), ordered by `month`.

### cohort_retention: `gold.cohort_retention`, `gold.report_cohort_retention`
- `units/cohort_retention/etl.sql:11-16` temp `tmp_cohorts`: `DATE_TRUNC('month', MIN(order_ts))::DATE`
  per customer → CTE.
- `:18-26` temp `tmp_activity`: `DATEDIFF(month, c.cohort_month, DATE_TRUNC('month', o.order_ts)::DATE)`
  between first-of-month dates (S-10) → `(year(m)*12+month(m)) - (year(c)*12+month(c))` or
  `datediff(MONTH, cohort_month, m)` (identical for first-of-month inputs [dbsql]).
  `COUNT(DISTINCT c.customer_id)` per (cohort, offset).
- `:28-37` INSERT join to cohort sizes (`COUNT(*)` from tmp_cohorts); `:39-40` drop temps.
- Golden 65 rows; cohorts 2025-01…2025-08.
- `report.sql:6` `ROUND(100.0 * active_buyers / cohort_size, 2)`: Redshift NUMERIC; Databricks
  `round(100.0 * active_buyers / cohort_size, 2)` (DECIMAL(13,6) intermediate, HALF_UP) matches all 65 rows
  (e.g. 70.4375… → `70.44`) [golden][dbsql]. Keep in DECIMAL (do not use DOUBLE).

---

## Wave 2: Orchestration

### exec_summary: `gold.exec_summary`, `gold.report_orchestration`
- `99_orchestration/exec_summary/etl.sql:5` `'as_of_2025-12-31'::VARCHAR(32)`, `:6` `DATE '2025-12-31'`.
- `:12-13` `SUM(revenue)`, `SUM(order_count)` from `mart.daily_revenue` → `10543825.25`, `20000`.
  (`total_orders` sums per-day distinct counts; an order belongs to exactly one day, so equals 20000.)
- `:14` `AVG(ltv)` from `mart.customer_ltv`, truncated at scale 2 (S-3): 7029.2168… → `7029.21`.
- `:15-16` `SUM(returned_qty)::NUMERIC(14,4) / SUM(sold_qty)::NUMERIC(14,4) * 100` → scale-15 truncation
  (S-4) → `5.013772053897100`.
- `:17-18` `SUM(avg_hours_to_deliver * delivered) / SUM(delivered)` from `mart.shipping_sla`:
  uses the already-truncated per-carrier `avg_hours_to_deliver` (NUMERIC(10,2)) weighted by `delivered`;
  result scale 4 → `71.2551` (= 71 + 3018/11830). Databricks:
  `CAST(FLOOR(SUM(avg_hours_to_deliver * delivered) / SUM(delivered), 4) AS DECIMAL(38,4))`, reading the
  gold shipping_sla table (not recomputing from shipments).
- Dependencies: reads gold daily_revenue, customer_ltv, returns_rate, shipping_sla → must run after wave 1a and 1b.

### Schedule: `99_orchestration/refresh_schedule.yaml:1-39`
- Job `nightly_mart_refresh`, cron `0 2 * * *`, `timezone: UTC` (`:3-5`).
- DAG: `load_core` → {`wave_1a` (5 units, `:10-17`), `wave_1b` (13 units, `:18-33`)} → `exec_summary`
  (`:34-36`, depends on both); `finance_export` UNLOAD depends on `wave_1b` only (`:37-39`).
- Lakeflow job equivalent: Quartz cron `0 0 2 * * ?` in `UTC`; one task per unit (or per wave) with
  `depends_on` mirroring the YAML; exec_summary depends on all 18 unit tasks; export task depends on
  all 13 wave-1b unit tasks.
- Every legacy unit fully rebuilds its mart (`DROP TABLE IF EXISTS` + `CREATE`), so `CREATE OR REPLACE TABLE`
  is the faithful per-run semantic; there is no incremental state between runs.

---

## Golden column impact index

| golden column(s) | rules |
|---|---|
| foundation customers.region, stores.region | F-1 (S-7) |
| foundation campaign_touches.payload | F-3 |
| customer_ltv.region, report_customer_ltv.region, geo_rollup.region, report_store_weekly.region | F-1 |
| customer_ltv.clean_phone | F-5 |
| customer_ltv.aov, report_customer_ltv.avg_ltv, exec_summary.avg_customer_ltv | S-3 |
| churn_flags.days_since_order | S-11 |
| report_churn_flags.avg_days_since_order, report_rfm_segments.avg_frequency | S-2 |
| shipping_sla.avg_hours_to_deliver | S-2 + S-10 |
| shipping_sla.max_hours_to_deliver, on_time_96h | S-10 (negative-duration rows) |
| shipping_sla.earliest_local_delivery_hour | S-12 |
| rfm_segments.r_tile, rfm_segment (and report grouping) | S-9 |
| rfm_segments.recency_days | S-10 day |
| store_weekly.week_start, week_end, week_number; report_store_weekly.active_weeks | S-10 week, S-17 |
| cohort_retention.month_offset | S-10 month |
| report_cohort_retention.retention_pct | S-15 |
| promo_lift.median_order_value, p90_order_value | S-5 |
| category_mix.revenue_share | S-6 |
| payment_mix.amount_share | S-4 (scale 4) |
| payment_mix.method, method_family, method_status | S-13 |
| returns_rate.return_rate_int | S-1 |
| returns_rate.return_pct, exec_summary.overall_return_pct | S-4 (scale 15) |
| exec_summary.avg_ship_hours | S-4 (scale 4) over truncated S-2 input |
| finance_monthly.fiscal_qtr, report_finance_export (grouping) | F-4 |
| product_perf.top_stores | S-8, S-9 tie order |
| geo_rollup.grouping_id | S-14 |
| attribution.* | S-18 |
