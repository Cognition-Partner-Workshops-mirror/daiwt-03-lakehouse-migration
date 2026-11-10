# DAIWT-03 target data model and rationalization (Wave 0 discovery)

Scope: the Redshift `core`/`mart` estate in `daiwt-03-redshift` (legacy repo, read-only baseline) mapped onto the
medallion layout of `daiwt-03-lakehouse-migration`. Legacy pointers are `path:line` in the legacy repo unless prefixed
`mig:` (migration repo, `main`).

## 1. Catalogs, schemas, volumes

| Environment | Catalog | Schemas | Source |
| --- | --- | --- | --- |
| prod | `daiwt_03_mig_prod` | `bronze`, `silver`, `gold` (fixed) | `mig:databricks.yml:52-65` |
| dev (per PR / per user) | `daiwt_03_mig_dev` | `bronze_<suffix>`, `silver_<suffix>`, `gold_<suffix>`; suffix defaults to `${workspace.current_user.short_name}`, CI uses `pr_<n>` | `mig:databricks.yml:6-15,24-46` |
| landing (prod only) | `daiwt_03_mig_prod.landing` | volumes `golden` (read-only baseline) and `bronze_landing` (currently empty) | UC listing |

- Golden volume layout: `/Volumes/daiwt_03_mig_prod/landing/golden/{manifest.json, inputs/D0/core.<table>.csv, outputs/D0/<unit>/<name>.csv}` (`mig:golden/README.md`). Only drop `D0` exists (manifest `drops`, `drops_reason`: full reload, no incremental loads).
- Parity resolves `<layer>.<table>` to `<layer>` in prod and `<layer>_<suffix>` in dev (`mig:src/parity/parity_check.py:198-211`).
- Legacy schema mapping: `core` -> `silver`, `mart` -> `gold` (`tools/legacy_redshift.py` `fetchOutput`: `{"silver": "core", "gold": "mart"}`); legacy schemas created at `legacy/redshift/00_foundation/01_schemas.sql:3-4`.
- UDFs `f_fiscal_qtr`, `f_clean_phone` live in Redshift `public` (`legacy/redshift/00_foundation/03_udfs.sql:4-17`). Target: UC SQL functions in `silver` (or inlined); see section 5.

### 1.1 Parity contract mechanics (drives every type decision below)
- `mig:src/parity/contract.json`: 48 outputs = 10 foundation tables (`silver.*`), 19 marts (`gold.*`, includes `gold.exec_summary`), 19 reports (`gold.report_<unit>`).
- The harness runs `SELECT <golden columns> FROM <catalog>.<schema>.<table>` through the Statement Execution API and compares the **rendered strings** to golden CSV cells (`\N` -> NULL) via an order-independent SHA-256 of rows (`mig:src/parity/parity_check.py:22-24,118-127,190-213`). There is no numeric tolerance and no type normalization: a column passes only if Databricks renders the identical string.
- Golden rendering (`tools/legacy_redshift.py` `renderCell`; manifest `csv_conventions`): decimals as fixed-point at the Redshift result scale, floats as Python `repr`, booleans `true/false`, timestamps `YYYY-MM-DD HH:MM:SS` (isoformat, no fraction present in any golden), dates `YYYY-MM-DD`, CHAR with padding preserved, SUPER as `JSON_SERIALIZE` text.
- Observed Databricks rendering (read-only probe on warehouse `6dc4b80538621b7b`, session TZ `Etc/UTC`):

| Databricks value | Rendered | Golden equivalent | Consequence |
| --- | --- | --- | --- |
| `TIMESTAMP_NTZ '2025-09-14 17:02:55'` | `2025-09-14T17:02:55.000` | `2025-09-14 17:02:55` | native timestamp columns do not match as-is |
| `TIMESTAMP` (LTZ) | `2025-09-14T17:02:55.000Z` | same | do not use LTZ |
| `CAST('NE' AS CHAR(4))` | `NE` | `NE  ` | Databricks does not pad; use `rpad(x,4,' ')` into STRING |
| `DECIMAL(12,2) 193.25`, `DECIMAL(18,2) 0` | `193.25`, `0.00` | `193.25`, `0.00` | match when the declared scale equals the golden scale |
| `DOUBLE 0.15411330152688182` | `0.15411330152688182` | same | match (shortest repr) for values in golden range |
| `parse_json(payload)` (VARIANT) | keys re-ordered alphabetically | original key order (`customer_ref,touches,meta`) | VARIANT does not round-trip the golden text |
| `BOOLEAN`, `DATE`, `BIGINT`/`INT` | `true`, `2025-01-01`, `17` | same | match |
| `DECIMAL(14,4)/DECIMAL(14,4)*100` | `DECIMAL(37,19)` `5.1169590643274853800` | `5.116959064327400` | Databricks division scale differs; cast/floor explicitly |

  Timestamp publication note (shared framework, not per unit): golden-facing timestamp columns either (a) are stored as `TIMESTAMP_NTZ` and the parity harness renders them `date_format(col,'yyyy-MM-dd HH:mm:ss')`, or (b) silver/gold keep a native `TIMESTAMP_NTZ` for computation and the published golden-facing column is `STRING` formatted `yyyy-MM-dd HH:mm:ss`. This model assumes (a)-style intent (native types in silver) and lists the exact rendering each column must produce; whichever option is chosen must be applied uniformly to the 7 timestamp columns in section 3 and the 2 in `gold.web_sessions`.

## 2. Bronze layer (raw landing)

Source: `inputs/D0/core.<table>.csv` in the golden volume (live exports; for 8 of 10 tables byte-identical to `data/seed/csv/<table>.csv`; `customers`/`stores` differ only in that the export carries the CHAR(4) blank padding, e.g. `NE  `, while the seed has `NE`). The legacy loader renders `\N` as NULL, numerics verbatim, booleans from `t/true/1`, SUPER via `JSON_PARSE` (`tools/legacy_redshift.py:35,102-111`, kinds at `:38-50`). CSV: UTF-8, header, RFC4180, `\N` = NULL, empty string distinct from NULL (no empty strings occur in any seed column).

Bronze tables keep every column as `STRING` (exact file text, `\N` already mapped to NULL via `nullValue => '\\N'`), plus optional lineage columns (`_source_file`, `_ingested_at`) that silver drops. Rationale: zero type coercion at landing; all Redshift type semantics are applied once in silver. Bronze tables are not parity targets (contract has no `bronze.*`). Recommended reader: `read_files(<path>, format=>'csv', header=>true, nullValue=>'\\N', schema=>'<all STRING>', multiLine=>true)` (campaign payloads contain quoted JSON).

| Bronze table | Columns (all STRING) | Rows | Nulls in data |
| --- | --- | --- | --- |
| `bronze.customers` | customer_id, email, first_name, last_name, phone, region, preferred_store_id, signup_date, is_business | 1500 | phone 181 |
| `bronze.stores` | store_id, region, store_name, city, state | 40 | - |
| `bronze.products` | product_id, sku, product_name, category, subcategory, unit_price, cost, active | 300 | - |
| `bronze.orders` | order_id, customer_id, store_id, order_ts, sales_channel, status | 20000 | - |
| `bronze.order_items` | order_item_id, order_id, product_id, quantity, unit_price, discount | 40938 | - |
| `bronze.payments` | payment_id, order_id, method, amount, paid_ts | 20000 | method 2826 |
| `bronze.returns` | return_id, order_item_id, quantity, reason, returned_ts | 2518 | reason 461 |
| `bronze.shipments` | shipment_id, order_id, carrier, ship_ts, delivered_ts | 12817 | delivered_ts 987 |
| `bronze.web_events` | event_id, customer_id, event_ts, event_type, page_url | 25000 | customer_id 3707 |
| `bronze.campaign_touches` | touch_id, customer_id, payload | 8000 | - |

## 3. Silver layer (typed core; parity targets `silver.<table>`, keys per `.migration/units.yaml:25-34`)

General type map (Redshift -> Databricks):

| Redshift | Databricks silver | Fidelity rule |
| --- | --- | --- |
| `BIGINT` / `INT` | `BIGINT` / `INT` | as-is |
| `VARCHAR(n)` | `STRING` | lengths are not enforced by Databricks STRING; all seed values fit (max email 31, page_url 6, product_name 20) |
| `CHAR(4)` | `STRING` = `rpad(rtrim(x), 4, ' ')` | blank padding must be materialized (golden `NE  `, `SW  `); comparisons/joins on region use the padded value consistently |
| `NUMERIC(12,2)` | `DECIMAL(12,2)` | scale 2 everywhere in seed |
| `TIMESTAMP` | `TIMESTAMP_NTZ` | no fractional seconds in any input; session TZ UTC; render per section 1.1 |
| `DATE` | `DATE` | |
| `BOOLEAN` | `BOOLEAN` | |
| `SUPER` | `STRING` (raw JSON text) for the parity column; `VARIANT` (`parse_json`) or `from_json` STRUCT for computation | VARIANT re-orders keys on render, so the golden-facing `payload` must stay the original text |

Physical design: `ENCODE lzo` is dropped (Delta/Parquet compression). `DISTKEY`/`DISTSTYLE ALL` are dropped (no distribution concept; small dimensions broadcast automatically). `SORTKEY` becomes liquid clustering (`CLUSTER BY`) only where it helps the downstream filters/joins; at these volumes (max 41k rows) clustering is optional and has no effect on outputs.

| # | Silver table | Legacy DDL | Columns -> Databricks type | Key (NOT NULL in legacy) | DISTKEY / DISTSTYLE | SORTKEY -> clustering | ENCODE |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `silver.customers` | `legacy/redshift/00_foundation/02_core_tables.sql:2-14` | customer_id BIGINT, email STRING, first_name STRING, last_name STRING, phone STRING, region STRING (CHAR(4) padded), preferred_store_id INT, signup_date DATE, is_business BOOLEAN | customer_id (`:3`) | DISTKEY(customer_id) `:13` -> drop | (customer_id) `:14` -> `CLUSTER BY (customer_id)` | email, region lzo `:4,:8` -> drop |
| 2 | `silver.stores` | `02_core_tables.sql:16-24` | store_id INT, region STRING (CHAR(4) padded), store_name STRING, city STRING, state STRING | store_id (`:17`) | DISTSTYLE ALL `:23` -> drop | (store_id) `:24` -> none needed (40 rows) | region lzo `:18` -> drop |
| 3 | `silver.products` | `02_core_tables.sql:26-37` | product_id INT, sku STRING, product_name STRING, category STRING, subcategory STRING, unit_price DECIMAL(12,2), cost DECIMAL(12,2), active BOOLEAN | product_id (`:27`) | DISTSTYLE ALL `:36` -> drop | (product_id) `:37` -> none needed (300 rows) | category lzo `:30` -> drop |
| 4 | `silver.orders` | `02_core_tables.sql:39-48` | order_id BIGINT, customer_id BIGINT, store_id INT, order_ts TIMESTAMP_NTZ, sales_channel STRING, status STRING | order_id (`:40`) | DISTKEY(customer_id) `:47` -> drop | (order_ts) `:48` -> `CLUSTER BY (order_ts)` optional | order_ts, sales_channel lzo `:43-44` -> drop |
| 5 | `silver.order_items` | `02_core_tables.sql:50-59` | order_item_id BIGINT, order_id BIGINT, product_id INT, quantity INT, unit_price DECIMAL(12,2), discount DECIMAL(12,2) | order_item_id (`:51`) | DISTKEY(order_id) `:58` -> drop | (order_id) `:59` -> `CLUSTER BY (order_id)` optional | - |
| 6 | `silver.payments` | `02_core_tables.sql:61-69` | payment_id BIGINT, order_id BIGINT, method STRING, amount DECIMAL(12,2), paid_ts TIMESTAMP_NTZ | payment_id (`:62`) | DISTKEY(order_id) `:68` -> drop | (order_id) `:69` -> optional | - |
| 7 | `silver.returns` | `02_core_tables.sql:71-79` | return_id BIGINT, order_item_id BIGINT, quantity INT, reason STRING, returned_ts TIMESTAMP_NTZ | return_id (`:72`) | DISTKEY(order_item_id) `:78` -> drop | (returned_ts) `:79` -> optional | - |
| 8 | `silver.shipments` | `02_core_tables.sql:81-89` | shipment_id BIGINT, order_id BIGINT, carrier STRING, ship_ts TIMESTAMP_NTZ, delivered_ts TIMESTAMP_NTZ | shipment_id (`:82`) | DISTKEY(order_id) `:88` -> drop | (ship_ts) `:89` -> optional | carrier lzo `:84` -> drop |
| 9 | `silver.web_events` | `02_core_tables.sql:91-99` | event_id BIGINT, customer_id BIGINT, event_ts TIMESTAMP_NTZ, event_type STRING, page_url STRING | event_id (`:92`) | DISTKEY(customer_id) `:98` -> drop | (event_ts) `:99` -> `CLUSTER BY (customer_id, event_ts)` matches the sessionization window | event_type lzo `:95` -> drop |
| 10 | `silver.campaign_touches` | `02_core_tables.sql:101-107` | touch_id BIGINT, customer_id BIGINT, payload STRING (exact JSON text) | touch_id (`:102`) | DISTKEY(customer_id) `:106` -> drop | (touch_id) `:107` -> optional | - |

Notes:
- Contract column types (`mig:src/parity/contract.json`, foundation entries) match the DDL: int8/int4/varchar/bpchar/numeric/timestamp/date/bool/super.
- Legacy `NOT NULL` on keys can be expressed as Delta `NOT NULL` constraints; keys are unique in the seed (capture verifies unique keys, manifest `format_exceptions`). PK/FK can be declared as informational UC constraints.
- `campaign_touches.payload` structure (all 8000 rows): `{customer_ref: BIGINT, touches: ARRAY<STRUCT<channel STRING, campaign_id STRING, ts STRING>>, meta: STRUCT<source STRING, batch INT>}`; 1-4 touches per row, 20003 touches total; `customer_ref` equals `customer_id` on every row. A typed view `silver.campaign_touch_events` (`touch_id, customer_id, campaign_id, channel, ts`) via `from_json` + `explode` serves `attribution` (see section 5).
- Region codes: `EAST, NRTH, SOTH, WEST` (4 chars) and `NE`, `SW` (padded to `NE  `, `SW  `). Each state maps to one region.

## 4. Gold layer: marts and reports

Rendering rules that apply throughout (from goldens and contract types): COUNT/SUM of INT -> `BIGINT`; money sums -> `DECIMAL(38,2)` (scale 2); line revenue expression everywhere is `quantity * (unit_price - discount)`. Redshift semantics that must be mirrored explicitly in Databricks:
- `AVG` over INT/BIGINT returns an integer truncated toward zero (Databricks returns DOUBLE): use `CAST(TRUNC(AVG(x)) AS BIGINT)` or `SUM(x) DIV COUNT(x)`.
- `AVG` over `NUMERIC(p,2)` returns scale 2 **truncated** (verified: `customer_ltv.aov` matches truncation on 1354/1354 rows, rounding on 685): `CAST(FLOOR(AVG(x), 2) AS DECIMAL(38,2))` for non-negative values (all relevant values are non-negative).
- NUMERIC division truncates at the Redshift result scale (Databricks rounds/widens); MEDIAN/PERCENTILE_CONT truncate to scale 2.
- INT/INT is integer division (`DIV`).
- NULLs sort last in ASC and first in DESC in Redshift; Databricks is the opposite for DESC (NULLS FIRST ASC by default). Write `NULLS LAST`/`NULLS FIRST` explicitly in every window `ORDER BY`.
- `DATEDIFF(unit, a, b)` counts unit boundaries crossed (hour/week/month/day), not elapsed intervals.
- `CHAR(4)` region keeps padding in output columns; `LISTAGG` output in `product_perf.top_stores` carries the codes without padding (`"EAST,NRTH,NE"`).

Physical design for marts: legacy `DISTSTYLE`/`DISTKEY`/`SORTKEY` on CTAS marts are dropped; marts are small (max 21280 rows) so no clustering is required. Legacy rebuilds each mart with `DROP TABLE` + `CREATE TABLE ... AS` every run (full refresh), so `CREATE OR REPLACE TABLE ... AS` is the faithful target. `.migration/units.yaml` `writes:` lists the mart names below.

Reports: the legacy `report.sql` is a SELECT whose result set is the golden; the target persists it as `gold.report_<unit>` (contract), produced from the unit's own gold mart (and silver where the legacy report joins `core`). Report `ORDER BY`/`LIMIT` matter only where `LIMIT` selects rows (basket_affinity, inventory_snapshot): parity is order-independent otherwise.

### 4.1 Wave 1a

**gold.daily_revenue** - `legacy/redshift/units/daily_revenue/etl.sql:2-14` (DISTSTYLE ALL `:4`, SORTKEY `:5` -> drop). Grain: order date x channel; key (order_date, sales_channel) (`.migration/units.yaml:46`). Reads orders JOIN order_items (inner, `:11-12`). 1460 rows.
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| order_date | date | DATE | `CAST(order_ts AS DATE)` (`TRUNC(ts)::DATE`, `:7`) |
| sales_channel | varchar | STRING | |
| order_count | int8 | BIGINT | `COUNT(DISTINCT order_id)` |
| revenue | numeric (scale 2) | DECIMAL(38,2) | `SUM(qty*(price-discount))` |

**gold.report_daily_revenue** - `daily_revenue/report.sql:2-8`. Grain month x channel; key (order_month, sales_channel); 48 rows. order_month DATE = `CAST(DATE_TRUNC('MONTH', order_date) AS DATE)`; order_count BIGINT = SUM; revenue DECIMAL(38,2) = SUM.

**gold.customer_ltv** - `customer_ltv/etl.sql:4-19` (DISTKEY/SORTKEY `:6-7` -> drop). Grain customer; key customer_id; 1500 rows (all customers, LEFT JOINs `:16-17`).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| customer_id | int8 | BIGINT | |
| region | bpchar | STRING padded to 4 | `:10` |
| clean_phone | varchar | STRING | `regexp_replace(phone,'[^0-9]','')`; NULL phone -> NULL (181) (`03_udfs.sql:12-17`) |
| order_count | int8 | BIGINT | `COUNT(DISTINCT o.order_id)`; 0 for customers without orders |
| ltv | numeric (2) | DECIMAL(38,2) | `COALESCE(SUM(...),0)` -> `0.00` for 146 customers |
| aov | numeric (2) | DECIMAL(38,2) | `AVG(unit_price - discount)` per order **line**, truncated to scale 2; NULL for 146 customers (`:14`) |
GROUP BY includes `c.phone` (`:18`); grain stays one row per customer.

**gold.report_customer_ltv** - `customer_ltv/report.sql:2-9`. Grain region (6 rows, padded keys). customers BIGINT `COUNT(*)`; orders BIGINT `SUM(order_count)`; total_ltv DECIMAL(38,2); avg_ltv DECIMAL(38,2) = AVG(ltv) truncated to scale 2 (NE `7118.14` vs rounded `7118.15`; SW `7457.51` vs `7457.52`).

**gold.geo_rollup** - `geo_rollup/etl.sql:3-18`. Grain grouping set; key (grouping_id, region, state); 21 rows = 6 regions + 14 states + 1 total. stores LEFT JOIN orders LEFT JOIN order_items (`:14-16`); `GROUPING SETS ((region),(state),())` (`:17`).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| grouping_id | int4 | INT | CASE on `GROUPING()` 1=region, 2=state, 3=total (`:5-9`) |
| region | bpchar | STRING padded | NULL on state/total rows |
| state | varchar | STRING | NULL on region/total rows |
| order_count | int8 | BIGINT | COUNT DISTINCT |
| revenue | numeric (2) | DECIMAL(38,2) | COALESCE(SUM,0) |
Databricks `GROUPING()` and `GROUPING SETS` are supported natively. **gold.report_geo_rollup** (`geo_rollup/report.sql:2-4`) is the identical projection (21 rows).

**gold.churn_flags** - `churn_flags/etl.sql:3-53`: plpgsql procedure, temp table, row-by-row FOR loop, `CALL`. Explicit DDL `:4-11`: customer_id BIGINT, last_order_date DATE, days_since_order INT, churn_flag VARCHAR(16) -> STRING. Grain customer; 1500 rows. Set-based equivalent: customers LEFT JOIN orders, `last_order_date = CAST(MAX(order_ts) AS DATE)` (`:24-28`); `days_since_order = DATEDIFF(DATE'2025-12-31', last_order_date)` as INT (NULL when no orders, 146 rows) (`:37-39`); flag: NULL -> `never_ordered`, `>180` -> `churned`, `>90` -> `at_risk`, else `active` (`:40-45`). The loop has no order-dependent state, so a single INSERT/CTAS is equivalent.

**gold.report_churn_flags** - `churn_flags/report.sql:2-7`. Grain churn_flag (4). customers BIGINT; avg_days_since_order int8 = integer AVG truncated (`active` 22.57 -> `22`, `at_risk` 115.3 -> `115`), NULL for `never_ordered`.

**gold.product_perf** - `product_perf/etl.sql:2-43` (DISTKEY/SORTKEY `:4-5` -> drop). Grain product; key product_id; 300 rows.
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| product_id | int4 | INT | |
| category | varchar | STRING | |
| units_sold | int8 | BIGINT | `SUM(quantity)` over all order_items, COALESCE 0 (`:28-33,37`) |
| revenue | numeric (2) | DECIMAL(18,2) | `::NUMERIC(18,2)` (`:31`), COALESCE 0 |
| top_stores | varchar | STRING | up to 3 **region** codes by units DESC, region ASC (`:7-27`), comma-joined, unpadded |
`top_stores` port: `array_join(transform(array_sort(collect_list(struct(-units, rtrim(region)))) , x -> x.col2), ',')` over the `rn <= 3` rows, or `concat_ws(',', ...)` with an ordered `collect_list`; ties resolved on padded region order (`ORDER BY units DESC, region`). Note `per_store` joins orders and stores (inner) while `agg` does not.

**gold.report_product_perf** - `product_perf/report.sql:2-8`. Grain category (6). products BIGINT `COUNT(*)`, units_sold BIGINT, revenue DECIMAL(38,2).

### 4.2 Wave 1b

**gold.store_weekly** - `store_weekly/etl.sql:2-17`. Grain store x ISO week; key (store_id, week_start); 2120 rows.
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| store_id | int4 | INT | |
| week_start | date | DATE | `CAST(DATE_TRUNC('WEEK', order_ts) AS DATE)` (Monday in both engines) |
| week_end | date | DATE | `DATE_ADD(week_start, 6)` |
| week_number | int8 | BIGINT | Redshift `DATEDIFF(week, DATE'2025-01-01', week_start)` = week boundaries crossed: `DATEDIFF(week_start, DATE_TRUNC('WEEK', DATE'2025-01-01')) DIV 7` (2024-12-30 -> 0, 2025-01-06 -> 1) |
| order_count | int8 | BIGINT | |
| revenue | numeric (2) | DECIMAL(38,2) | |

**gold.report_store_weekly** - `store_weekly/report.sql:2-10` (joins `core.stores` -> `silver.stores`). Grain store (40). region STRING padded; active_weeks BIGINT = week-boundary DATEDIFF(MIN, MAX week_start) + 1; order_count BIGINT; revenue DECIMAL(38,2).

**gold.category_mix** - `category_mix/etl.sql:2-16`. Grain category (6). units_sold BIGINT; revenue DECIMAL(38,2); revenue_share float8 -> DOUBLE = `RATIO_TO_REPORT(revenue) OVER ()` -> `CAST(revenue AS DOUBLE) / SUM(CAST(revenue AS DOUBLE)) OVER ()` (`try_divide` for a zero total). Golden values are shortest-repr doubles (`0.15411330152688182`); the double division must produce the identical bit pattern. **gold.report_category_mix** (`category_mix/report.sql:2-4`) = same 6 rows.

**gold.basket_affinity** - `basket_affinity/etl.sql:2-12`. Grain product pair (a < b); key (product_id_a, product_id_b); `HAVING COUNT(DISTINCT order_id) >= 5`; 50 rows; types INT, INT, BIGINT.
**gold.report_basket_affinity** - `basket_affinity/report.sql:2-10`: adds `pair` STRING = `product_name_a || ' + ' || product_name_b` (joins `silver.products` twice), `ORDER BY pair_orders DESC, product_id_a, product_id_b LIMIT 50` (key order is a total order, so the top-50 is deterministic).

**gold.web_sessions** (unit `sessionization`) - `sessionization/etl.sql:2-42`. Grain customer x session; key (customer_id, session_id); 21280 rows; events with NULL customer_id excluded (`:22`, 3707 rows).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| customer_id | int8 | BIGINT | |
| session_id | int8 | BIGINT | running `SUM(new_session)` per customer ordered by (event_ts, event_id) `ROWS UNBOUNDED PRECEDING` (`:29-31`); starts at 1 |
| session_start_ts / session_end_ts | timestamp | TIMESTAMP_NTZ | MIN/MAX(event_ts); render `yyyy-MM-dd HH:mm:ss` |
| event_count | int8 | BIGINT | |
| checkout_events | int8 | BIGINT | `SUM(CASE event_type='checkout')` |
New session when LAG is NULL or `DATEDIFF(second, prev, ts) > 1800` (`:12-20`). Second-boundary count equals elapsed whole seconds here (no fractional seconds): use `unix_timestamp`-free wall-clock arithmetic, e.g. `timestampdiff(SECOND, prev, ts)` on TIMESTAMP_NTZ.
**gold.report_sessionization** - `sessionization/report.sql:2-8`. Grain customer (1500 rows: every customer appears). sessions, events, checkout_sessions BIGINT (`checkout_sessions` is `SUM(checkout_events)`).

**gold.shipping_sla** - `shipping_sla/etl.sql:3-17`. Grain carrier (4).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| carrier | varchar | STRING | |
| shipments | int8 | BIGINT | COUNT(*) |
| delivered | int8 | BIGINT | COUNT(delivered_ts) |
| in_flight | int8 | BIGINT | difference |
| avg_hours_to_deliver | numeric (2) | DECIMAL(10,2) | `AVG(DATEDIFF(hour,...))` is an integer AVG (truncated) cast to NUMERIC(10,2): `CAST(TRUNC(AVG(h)) AS DECIMAL(10,2))` -> `71.00` |
| max_hours_to_deliver | int8 | BIGINT | MAX(h) |
| on_time_96h | int8 | BIGINT | `SUM(CASE WHEN h <= 96 ...)` (NULL h counts 0) |
| earliest_local_delivery_hour | int4 | INT | `MIN(HOUR(from_utc_timestamp(delivered_ts,'America/Los_Angeles')))` (`:13-14`) |
`h` = Redshift `DATEDIFF(hour, ship_ts, delivered_ts)` = hour boundaries crossed = `(epoch_seconds(date_trunc('HOUR', delivered_ts)) - epoch_seconds(date_trunc('HOUR', ship_ts))) DIV 3600` computed in wall-clock (TIMESTAMP_NTZ) arithmetic; it can be negative (min `-66`) and the target must keep the sign.
**gold.report_shipping_sla** - `shipping_sla/report.sql:2-5`: same rows without `earliest_local_delivery_hour`.

**gold.rfm_segments** - `rfm_segments/etl.sql:3-37`. Grain customer (1500).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| customer_id | int8 | BIGINT | |
| recency_days | int8 | BIGINT | `DATEDIFF(DATE'2025-12-31', CAST(MAX(order_ts) AS DATE))`; NULL for 146 |
| frequency | int8 | BIGINT | COUNT DISTINCT orders (0 allowed) |
| monetary | numeric (2) | DECIMAL(38,2) | COALESCE(SUM,0) |
| r_tile / f_tile / m_tile | int8 | BIGINT | `NTILE(5)`; r: `ORDER BY recency_days ASC NULLS LAST, customer_id`; f: `frequency DESC NULLS FIRST, customer_id`; m: `monetary DESC NULLS FIRST, customer_id` (`:23-25`) |
| rfm_segment | varchar | STRING | `concat(r,f,m)` (3 chars) |
Redshift ASC puts NULL last, so the 146 NULL-recency customers land in r_tile 5 (observed); each tile holds exactly 300 customers.
**gold.report_rfm_segments** - `rfm_segments/report.sql:2-8`. Grain segment (103). customers BIGINT; total_monetary DECIMAL(38,2); avg_frequency int8 = integer AVG truncated (segment `111`: 21.30 -> `21`).

**gold.promo_lift** - `promo_lift/etl.sql:2-18`. Grain channel (4). order_count BIGINT; median_order_value / p90_order_value numeric scale 2 = continuous-percentile interpolation over `order_total` (NUMERIC scale 2), **truncated** to scale 2 (mobile median 390.215 -> `390.21`; p90 1093.965 -> `1093.96`). Port: `percentile_cont(0.5|0.9) WITHIN GROUP (ORDER BY order_total)` returns DOUBLE in Databricks, so compute the interpolation in DECIMAL (`ROW_NUMBER`, n, `pos = 1 + p*(n-1)`, lower/upper rows) then `CAST(FLOOR(x, 2) AS DECIMAL(38,2))`. **gold.report_promo_lift** is the same projection.

**gold.payment_mix** - `payment_mix/etl.sql:2-17`. Grain method (5, including `unknown` for the 2826 NULL methods). method STRING `NVL(method,'unknown')`; method_family STRING via DECODE -> `CASE` (`card`->CARD, `cash`->CASH, `wallet`/`gift_card`->DIGITAL, else OTHER); method_status STRING `NVL2` -> `CASE WHEN method IS NULL THEN 'missing' ELSE 'captured'`; payment_count BIGINT; amount_total DECIMAL(38,2); amount_share numeric **scale 4 truncated**: `CAST(FLOOR(SUM(amount) / SUM(SUM(amount)) OVER (), 4) AS DECIMAL(38,4))` (card 0.427603... -> `0.4276`).
**gold.report_payment_mix** - `payment_mix/report.sql:2-7`. Grain method_family (4). payment_count BIGINT; amount_total DECIMAL(38,2).

**gold.returns_rate** - `returns_rate/etl.sql:3-15`. Grain category (6). order_items JOIN products LEFT JOIN returns on order_item_id (`:11-13`).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| category | varchar | STRING | |
| sold_qty | int8 | BIGINT | `SUM(oi.quantity)` |
| returned_qty | int8 | BIGINT | `COALESCE(SUM(r.quantity),0)` |
| return_rate_int | int8 | BIGINT | integer division `returned DIV sold` (all `0`) |
| return_pct | numeric (15) | DECIMAL(38,15) | `NUMERIC(14,4)/NUMERIC(14,4)` truncates the quotient at scale 15, then `* 100` keeps scale 15: `CAST(FLOOR(CAST(r AS DECIMAL(14,4)) / CAST(s AS DECIMAL(14,4)), 15) * 100 AS DECIMAL(38,15))` -> `5.116959064327400` |
**gold.report_returns_rate** - same projection (`returns_rate/report.sql:2-4`).

**gold.attribution** - `attribution/etl.sql:2-10`. PartiQL unnest `FROM core.campaign_touches t, t.payload.touches tc` (`:8`) -> `LATERAL VIEW explode(from_json(payload, ...).touches)` or `variant_explode(parse_json(payload):touches)`. Grain campaign x channel (100). campaign_id STRING (`::VARCHAR(16)`), touch_channel STRING, touches BIGINT COUNT(*), customers_reached BIGINT COUNT(DISTINCT customer_id).
**gold.report_attribution** - `attribution/report.sql:2-7`. Grain campaign (20). touches, customers_reached BIGINT = SUMs of the mart columns.

**gold.inventory_snapshot** - `inventory_snapshot/etl.sql:3-41`: plpgsql procedure with staging temp table and DELETE/INSERT upsert, `CALL sp_upsert_inventory('2025-12-31')`. DDL `:4-11`: product_id INT, snapshot_date DATE, units_sold BIGINT, on_hand INT. Grain product (300). Since the table is dropped and recreated first (`:3`), the result equals one CTAS: products LEFT JOIN `SUM(quantity)` per product; units_sold `COALESCE(...,0)`; on_hand `CAST(GREATEST(500 - units_sold, 0) AS INT)`; snapshot_date `DATE'2025-12-31'`. A `MERGE` keyed on product_id is the idiomatic equivalent of the DELETE/INSERT if incremental semantics are kept.
**gold.report_inventory_snapshot** - `inventory_snapshot/report.sql:2-5`: `ORDER BY on_hand ASC, product_id LIMIT 50` (total order; deterministic).

**gold.finance_monthly** (unit `finance_export`) - `finance_export/etl.sql:3-16`. Grain month (12).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| month | date | DATE | `CAST(DATE_TRUNC('MONTH', order_ts) AS DATE)` |
| fiscal_year | int4 | INT | `month >= 2 ? year : year - 1` (`:6-9`) |
| fiscal_qtr | varchar | STRING | `f_fiscal_qtr`: `'Q' || ((((month + 9) % 12) / 3) + 1)` with INT division (`03_udfs.sql:8`) -> `concat('Q', CAST((((month(d) + 9) % 12) DIV 3) + 1 AS STRING))`. Legacy output: Mar-May Q1, Jun-Aug Q2, Sep-Nov Q3, Dec-Feb Q4 (golden: Jan `2024,Q4`, Feb `2025,Q4`, Mar `2025,Q1`, Dec `2025,Q4`) |
| order_count | int8 | BIGINT | |
| revenue | numeric (2) | DECIMAL(38,2) | |
**gold.report_finance_export** - `finance_export/report.sql:2-7`. Grain (fiscal_year, fiscal_qtr) (5 rows; `2025,Q4` aggregates Feb and Dec 2025).
`export.sql:3-8` (`UNLOAD ... CSV HEADER PARALLEL OFF`) is not captured (`units.yaml` capture_skip; manifest `skipped_branches`). Target: write one CSV with header from `gold.finance_monthly ORDER BY month` into a UC volume (e.g. a `gold` exports volume) from the job; not a parity target.

**gold.cohort_retention** - `cohort_retention/etl.sql:2-40` (explicit DDL `:3-9`: cohort_month DATE, month_offset INT, cohort_size BIGINT, active_buyers BIGINT; SORTKEY -> drop). Temp tables `tmp_cohorts` (`:12-16`) and `tmp_activity` (`:19-26`) become CTEs. Grain (cohort_month, month_offset) (65). month_offset = Redshift `DATEDIFF(month, cohort, month_of_order)` on month-start dates = `CAST(months_between(m, cohort) AS INT)` (exact on month starts) or `(year*12+month)` difference.
**gold.report_cohort_retention** - `cohort_retention/report.sql:2-8`: adds retention_pct numeric scale 2 = `ROUND(100.0 * active_buyers / cohort_size, 2)` (half-up rounding, e.g. 66.382 -> `66.38`, 70.4376 -> `70.44`); cast to `DECIMAL(38,2)` so `100` renders `100.00`.

### 4.3 Wave 2

**gold.exec_summary** (unit `orchestration`) - `99_orchestration/exec_summary/etl.sql:3-18`. Grain 1 row; key snapshot_label. Reads gold marts only (`units.yaml` reads: daily_revenue, customer_ltv, returns_rate, shipping_sla).
| column | golden type | Databricks | rule |
| --- | --- | --- | --- |
| snapshot_label | varchar | STRING | `'as_of_2025-12-31'` |
| as_of_date | date | DATE | `DATE'2025-12-31'` |
| total_revenue | numeric (2) | DECIMAL(38,2) | SUM(daily_revenue.revenue) = `10543825.25` |
| total_orders | int8 | BIGINT | SUM(order_count) = `20000` |
| avg_customer_ltv | numeric (2) | DECIMAL(38,2) | AVG(customer_ltv.ltv) truncated at scale 2 (7029.2168 -> `7029.21`) |
| overall_return_pct | numeric (15) | DECIMAL(38,15) | same truncation formula as `returns_rate.return_pct` over totals -> `5.013772053897100` |
| avg_ship_hours | numeric (4) | DECIMAL(38,4) | `SUM(avg_hours_to_deliver * delivered) / SUM(delivered)` truncated at scale 4 -> `71.2551` (built from the per-carrier `avg_hours_to_deliver` values) |
**gold.report_orchestration** = same single row (`exec_summary/report.sql:2-5`).
Schedule `refresh_schedule.yaml:3-39` (`0 2 * * *` UTC; load_core -> wave_1a, wave_1b in parallel -> exec_summary; finance_export export after wave_1b) becomes one Lakeflow job with the same task DAG; no golden.

## 5. Rationalization (output-preserving)

All items below are refactors that keep every golden column identical; they are optional and can be adopted unit by unit.

1. **`silver.order_lines` view** (line revenue): `quantity * (unit_price - discount) AS line_revenue` is recomputed in 13 places: `daily_revenue/etl.sql:10`, `customer_ltv/etl.sql:13`, `geo_rollup/etl.sql:13`, `product_perf/etl.sql:31`, `store_weekly/etl.sql:13`, `category_mix/etl.sql:11`, `rfm_segments/etl.sql:12`, `promo_lift/etl.sql:7`, `finance_export/etl.sql:12`, plus quantity rollups in `product_perf/etl.sql:10,30`, `inventory_snapshot/etl.sql:22`, `returns_rate/etl.sql:6`. A view `order_items JOIN orders` exposing `order_id, order_item_id, product_id, quantity, line_revenue, customer_id, store_id, order_ts, order_date, sales_channel, status` serves daily_revenue, store_weekly, finance_export, promo_lift, product_perf (per-store), cohort_retention. Keep LEFT JOIN marts (customer_ltv, geo_rollup, rfm_segments) on their own driving table so customers/stores without orders remain.
2. **`silver.order_totals`** (order grain, `SUM(line_revenue)` per order with channel/customer/store/order_ts): reused by `promo_lift/etl.sql:4-11`; also an equivalent basis for order counts.
3. **`silver.customer_order_stats`** (per customer: `last_order_ts`, `order_count`, `monetary`, line `AVG`): `customer_ltv/etl.sql:12-14`, `churn_flags/etl.sql:24-28`, `rfm_segments/etl.sql:9-16`, `cohort_retention/etl.sql:13-16` (first order) all aggregate orders per customer. One view from customers LEFT JOIN orders LEFT JOIN order_items giving `MIN/MAX(order_ts)`, `COUNT(DISTINCT order_id)`, `COALESCE(SUM(line_revenue),0)`, `SUM(unit_price-discount)`, `COUNT(order_item_id)` lets each mart derive its columns (aov truncation, recency, churn flag) without changing values. `customer_ltv.ltv` and `rfm_segments.monetary` are the same expression over the same join (`customer_ltv/etl.sql:13`, `rfm_segments/etl.sql:12`) and match row for row in the goldens (customer 1: `12440.40` in both).
4. **`silver.product_sales`** (per product: `SUM(quantity)`, revenue): `product_perf/etl.sql:28-34` and `inventory_snapshot/etl.sql:21-24` compute the same `SUM(quantity)` per product from order_items (golden product 1: `166` in both).
5. **`silver.campaign_touch_events`**: typed explode of the JSON payload, isolates SUPER/PartiQL handling in one place for `attribution`.
6. **Shared SQL functions** (UC, `silver` schema): `fiscal_qtr(d DATE) RETURNS STRING` and `clean_phone(p STRING) RETURNS STRING` mirroring `03_udfs.sql:4-17`; `rs_datediff_hour(a,b)`, `rs_datediff_week(a,b)` (boundary-count semantics); `rs_pad4(x)` for CHAR(4); `rs_trunc_avg_dec2`, `rs_pct15(num, den)` for the return_pct formula (used by `returns_rate/etl.sql:9-10` and `exec_summary/etl.sql:15-16`). Centralizing these Redshift-compatibility semantics provides consistent parity behavior.
7. **Report persistence pattern**: every `gold.report_<unit>` is a projection/aggregate of its own mart; a uniform `CREATE OR REPLACE TABLE gold.report_<unit> AS <ported report.sql>` step per unit keeps the contract shape uniform. Reports that are pure projections (geo_rollup, category_mix, shipping_sla, promo_lift, returns_rate, orchestration) could be views, but the contract treats them as tables, and persisted tables keep parity reads cheap.
8. Not merged on purpose: `daily_revenue`/`store_weekly`/`finance_export` aggregate the same lines at different grains; rolling one up from another (e.g. finance from daily) is exact for sums and distinct order counts only because an order has a single timestamp, but each unit is kept independent so its parity stays local.

## 6. Type-fidelity checklist for parity

| Area | Columns | Requirement |
| --- | --- | --- |
| CHAR(4) padding | customers.region, stores.region, customer_ltv.region, report_customer_ltv.region, geo_rollup(.report).region, report_store_weekly.region | `rpad(...,4,' ')` STRING; padded `NE  `, `SW  `; `top_stores` unpadded |
| Timestamps | orders.order_ts, payments.paid_ts, returns.returned_ts, shipments.ship_ts/delivered_ts, web_events.event_ts, web_sessions.session_start_ts/session_end_ts | value `yyyy-MM-dd HH:mm:ss`, no fraction, no `T`, no zone (section 1.1 publication note) |
| SUPER | campaign_touches.payload | original JSON text byte-for-byte |
| Decimal scale 2 | all money sums, aov, avg_ltv, median/p90, avg_hours_to_deliver, retention_pct | declared scale 2; AVG/percentile truncate, retention_pct rounds |
| Decimal scale 4 | payment_mix.amount_share (truncate), exec_summary.avg_ship_hours (truncate) | DECIMAL(38,4) |
| Decimal scale 15 | returns_rate(.report).return_pct, exec_summary.overall_return_pct | quotient truncated at 15, times 100 |
| Integer averages | report_churn_flags.avg_days_since_order, report_rfm_segments.avg_frequency, shipping_sla avg base | truncate toward zero, BIGINT |
| Integer division | returns_rate.return_rate_int, fiscal_qtr | `DIV` |
| Double | category_mix(.report).revenue_share | DOUBLE, identical bits to Redshift float8 division |
| NULL ordering | rfm_segments tiles | explicit NULLS LAST / FIRST |
| Boundary DATEDIFF | shipping_sla hours, store_weekly week_number/active_weeks, cohort month_offset, sessionization seconds, churn/rfm days | boundary count in wall-clock time, sign preserved |
| Booleans | customers.is_business, products.active | BOOLEAN renders `true/false` |
| Session TZ | all | warehouse session TZ is UTC (`Etc/UTC` observed); goldens captured with UTC sessions (manifest `session_timezone`) |
