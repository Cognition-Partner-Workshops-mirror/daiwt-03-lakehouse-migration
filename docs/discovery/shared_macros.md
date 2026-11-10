# DAIWT-03 Discovery: shared library and foundation DDL (`shared_macros.md`)

Scope: `legacy/redshift/00_foundation/{01_schemas,02_core_tables,03_udfs}.sql`, the two legacy SQL UDFs, and Redshift idioms that recur across the 18 wave-1 units plus `99_orchestration`. Every legacy pointer is `path:line` in `Cognition-Partner-Workshops-mirror/daiwt-03-redshift` (main). Target layout refers to `Cognition-Partner-Workshops-mirror/daiwt-03-lakehouse-migration` (main).

**Analyst evidence (retained from the supplied document; not rerun during this handover).** Each "verified" macro below was run read-only on the Serverless Starter Warehouse (`6dc4b80538621b7b`) against the D0 golden inputs in `/Volumes/daiwt_03_mig_prod/landing/golden/inputs/D0/core.*.csv`. Its output was compared with the D0 golden outputs as a multiset (`EXCEPT ALL` in both directions, string-cast). "0/0" means no row differed in either direction.

Source session facts (golden `manifest.json` → `source`, `session_timezone`): the source ran on Redshift Serverless with session time zone UTC. CSV NULLs are written `\N`, CHAR padding is kept, and SUPER values are written with `JSON_SERIALIZE`.

---

## 1. Schemas

| Legacy | Pointer | Target |
| --- | --- | --- |
| `CREATE SCHEMA IF NOT EXISTS core` | `legacy/redshift/00_foundation/01_schemas.sql:3` | `bronze` (raw copy of the golden input CSVs) and `silver` (typed tables; these are the 10 foundation parity outputs `silver.<table>`, per `.migration/units.yaml:25-34`) |
| `CREATE SCHEMA IF NOT EXISTS mart` | `legacy/redshift/00_foundation/01_schemas.sql:4` | `gold` (`gold.<mart>`; reports are `gold.report_<unit>` in `src/parity/contract.json`) |
| UDFs are created without a schema qualifier (`legacy/redshift/00_foundation/03_udfs.sql:4,12`); resolution follows the source search path | — | see §3.3 |

Target schema provisioning is separate from unit SQL: the bundle creates dev schemas; Terraform owns prod schemas. In dev they are `bronze_<suffix>`/`silver_<suffix>`/`gold_<suffix>` in `daiwt_03_mig_dev` (`databricks.yml` `targets.dev.resources.schemas`). In prod they are the fixed `bronze`/`silver`/`gold` in `daiwt_03_mig_prod` (`databricks.yml` `targets.prod.variables`). The migrated foundation SQL must therefore never run `CREATE SCHEMA`.

## 2. Core table DDL plan (Redshift → Delta)

### 2.1 Physical attributes

| Redshift clause | Where | Target handling |
| --- | --- | --- |
| `DISTKEY(col)` / `DISTSTYLE ALL` | `legacy/redshift/00_foundation/02_core_tables.sql:13,23,36,47,58,68,78,88,98,106` | Drop. Delta has no equivalent. Optional: `CLUSTER BY (<same col>)` (liquid clustering) on the larger tables (`orders`, `order_items`, `web_events`). This only affects performance, not results. |
| `SORTKEY(col)` | `legacy/redshift/00_foundation/02_core_tables.sql:14,24,37,48,59,69,79,89,99,107` | Drop, or fold into the same `CLUSTER BY`. Physical row order is not a parity requirement; preserve explicit ordering used by windows, LISTAGG and LIMIT. |
| `ENCODE lzo` | `legacy/redshift/00_foundation/02_core_tables.sql:4,8,18,30,43,44,84,95` | Drop. Delta/Parquet compression is automatic. |
| `IDENTITY` | none in foundation DDL | n/a. Keys are supplied by the seed. |
| `DEFAULT` | none in foundation DDL | n/a |
| `NOT NULL` | first column of every table (`legacy/redshift/00_foundation/02_core_tables.sql:3,17,27,40,51,62,72,82,92,102`) | Keep as Delta `NOT NULL` (enforced). |
| PK / FK / UNIQUE | none declared | Optional informational `PRIMARY KEY` on the parity key (`units.yaml:25-34`). This is not required, and Delta does not enforce it. |

### 2.2 Column type mapping (applies to all 10 tables)

| Redshift type (OID in golden meta) | Columns | Delta type | Notes |
| --- | --- | --- | --- |
| `BIGINT` (int8, 20) | `*_id` BIGINT columns | `BIGINT` | exact |
| `INT` (int4, 23) | `store_id`, `product_id`, `preferred_store_id`, `quantity` | `INT` | exact |
| `NUMERIC(12,2)` (1700) | `unit_price`, `cost`, `discount`, `amount` | `DECIMAL(12,2)` | Exact. Golden strings keep 2 decimal places (`379.92`). |
| `VARCHAR(n)` (1043) | text columns | `STRING` | Optional `VARCHAR(n)`. Databricks VARCHAR checks length but does not pad. `STRING` is simpler. |
| `CHAR(4)` (bpchar, 1042) | `customers.region` (`:8`), `stores.region` (`:18`) | `STRING` holding the **blank-padded value**: `rpad(region, 4, ' ')` at load | Golden keeps the padding (`'NE  '`, `'SW  '`; 174 customers, 4 stores each). Databricks `CHAR(4)` does **not** return trailing blanks (verified: `CAST('NE' AS CHAR(4)) || '\|'` = `NE\|`), so pad explicitly and store as STRING. See macro `rpad_char`. |
| `DATE` (1082) | `signup_date` | `DATE` | |
| `TIMESTAMP` (1114, without time zone) | `order_ts`, `paid_ts`, `returned_ts`, `ship_ts`, `delivered_ts`, `event_ts` | `TIMESTAMP_NTZ` | Wall-clock values with no zone, matching Redshift `TIMESTAMP`. `TIMESTAMP` (LTZ) would make results depend on the session time zone. |
| `BOOLEAN` (16) | `is_business`, `active` | `BOOLEAN` | Golden renders `true`/`false`. |
| `SUPER` (4000) | `campaign_touches.payload` (`:104`) | `STRING` (exact JSON text). Parse with `parse_json(payload)` (VARIANT) where it is used. | The golden `silver.campaign_touches.payload` is the `JSON_SERIALIZE` text. Storing it as `VARIANT` would change the text: `to_json(parse_json(payload))` reorders object keys alphabetically, and 8000/8000 rows came out different. Keep it as STRING for foundation parity. Downstream units `parse_json` it (verified for `attribution`, 0/0). |

### 2.3 Proposed target DDL (silver; bronze uses the same columns)

```sql
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.customers') (
  customer_id BIGINT NOT NULL, email STRING, first_name STRING, last_name STRING, phone STRING,
  region STRING /* CHAR(4), rpad'ed */, preferred_store_id INT, signup_date DATE, is_business BOOLEAN);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.stores') (
  store_id INT NOT NULL, region STRING /* CHAR(4) */, store_name STRING, city STRING, state STRING);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.products') (
  product_id INT NOT NULL, sku STRING, product_name STRING, category STRING, subcategory STRING,
  unit_price DECIMAL(12,2), cost DECIMAL(12,2), active BOOLEAN);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.orders') (
  order_id BIGINT NOT NULL, customer_id BIGINT, store_id INT, order_ts TIMESTAMP_NTZ,
  sales_channel STRING, status STRING);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.order_items') (
  order_item_id BIGINT NOT NULL, order_id BIGINT, product_id INT, quantity INT,
  unit_price DECIMAL(12,2), discount DECIMAL(12,2));
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.payments') (
  payment_id BIGINT NOT NULL, order_id BIGINT, method STRING, amount DECIMAL(12,2), paid_ts TIMESTAMP_NTZ);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.returns') (
  return_id BIGINT NOT NULL, order_item_id BIGINT, quantity INT, reason STRING, returned_ts TIMESTAMP_NTZ);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.shipments') (
  shipment_id BIGINT NOT NULL, order_id BIGINT, carrier STRING, ship_ts TIMESTAMP_NTZ, delivered_ts TIMESTAMP_NTZ);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.web_events') (
  event_id BIGINT NOT NULL, customer_id BIGINT, event_ts TIMESTAMP_NTZ, event_type STRING, page_url STRING);
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.campaign_touches') (
  touch_id BIGINT NOT NULL, customer_id BIGINT, payload STRING /* SUPER JSON text */);
```

### 2.4 Load semantics

- Legacy loads the seed with `INSERT ... VALUES`. `\N` becomes SQL `NULL`, booleans become `true`/`false`, and SUPER values go through `JSON_PARSE` (`tools/legacy_redshift.py:102-110,154`). Each run is a full reload: `DROP SCHEMA ... CASCADE`, then recreate (`tools/legacy_redshift.py:137-138`). Golden `drops_reason`: "full-reload ETL, no incremental loads".
- Target: bronze = `read_files('<golden_path>/inputs/D0/core.<t>.csv', format=>'csv', header=>true, nullValue=>'\\N', inferSchema=>false, multiLine=>true, escape=>'"')`, written as all-STRING columns. Silver = `CAST` to the §2.2 types, with `rpad(region,4,' ')` for the CHAR columns. In the inputs, NULL appears only as `\N` (customers.phone 181 rows, payments.method 2826, shipments.delivered_ts 987, returns.reason 461, web_events.customer_id 3707), and no column holds empty strings, so the reader options above keep NULL and '' distinct.
- `read_files` needs a constant path. Per-catalog paths therefore need one `BEGIN ... END` block with `EXECUTE IMMEDIATE ... USING`, or a path built in the job and passed as a parameter (`databricks.yml` `var.golden_path`).
- Foundation parity row counts (`src/parity/contract.json`): customers 1500, stores 40, products 300, orders 20000, order_items 40938, payments 20000, returns 2518, shipments 12817, web_events 25000, campaign_touches 8000.

---

## 3. Legacy UDFs → shared SQL functions

### 3.1 `f_fiscal_qtr(d DATE) RETURNS VARCHAR(8)` — `legacy/redshift/00_foundation/03_udfs.sql:4-9`

- Body (`:8`): `'Q' || ((((EXTRACT(MONTH FROM $1)::INT + 9) % 12) / 3) + 1)::VARCHAR`. `/` on INT is integer division, truncating toward zero. `IMMUTABLE`.
- Month → result as legacy computes it at `:8`: Jan Q4, Feb Q4, Mar Q1, Apr Q1, May Q1, Jun Q2, Jul Q2, Aug Q2, Sep Q3, Oct Q3, Nov Q3, Dec Q4. The target must mirror this expression. The golden follows it (`golden/finance_export/finance_monthly.csv`: `2025-02-01,2025,Q4`, `2025-03-01,2025,Q1`).
- NULL input → `EXTRACT` is NULL, and `'Q' || NULL` = NULL.
- Used once: `legacy/redshift/units/finance_export/etl.sql:10` as `f_fiscal_qtr(TRUNC(o.order_ts)::DATE)`. The fiscal year is computed separately and inline at `legacy/redshift/units/finance_export/etl.sql:6-9`.
- Target (verified: all 12 months match the table above, NULL → NULL, `finance_monthly` 0/0):

```sql
CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :silver_schema || '.f_fiscal_qtr')(d DATE)
RETURNS STRING
DETERMINISTIC
RETURN 'Q' || CAST(((((month(d) + 9) % 12) DIV 3) + 1) AS STRING);
```

`DIV` is required. Plain `/` returns a DOUBLE and would produce `Q1.666…`-style values.

### 3.2 `f_clean_phone(p VARCHAR) RETURNS VARCHAR(32)` — `legacy/redshift/00_foundation/03_udfs.sql:12-17`

- Body (`:16`): `REGEXP_REPLACE($1, '[^0-9]', '')`. This removes every non-digit and keeps all digits, including a leading country code (`+1 (086) 441 - 1347` → `10864411347`; `(079) 077-9946` → `0790779946`).
- NULL → NULL. A string with no digits → `''` (empty string, not NULL). In D0, 181 customer phones are NULL and none are digit-free.
- Used once: `legacy/redshift/units/customer_ltv/etl.sql:11`.
- Target (verified: 1500 customers 0/0, including the 181 NULLs; `customer_ltv` 0/0):

```sql
CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :silver_schema || '.f_clean_phone')(p STRING)
RETURNS STRING
DETERMINISTIC
RETURN regexp_replace(p, '[^0-9]', '');
```

### 3.3 Where the UDFs live and how units call them

- Proposed owner: the `foundation` unit (wave 0) runs `src/sql/units/foundation.sql`, which ends with the two `CREATE OR REPLACE FUNCTION` statements. It creates them in the suffix-scoped silver schema (`daiwt_03_mig_dev.silver_pr_<n>` / `daiwt_03_mig_prod.silver`), so each PR deployment gets its own copy. Dev cleanup drops them with the schema (CASCADE). In prod, `CREATE OR REPLACE` makes reruns idempotent.
- Callers: `customer_ltv`, `finance_export`. Each is to declare `"depends_on": ["foundation"]` in `src/sql/units/registry.json`; their silver inputs already require this. Call through the job parameters, never a hard-coded catalog: `IDENTIFIER(:catalog || '.' || :silver_schema || '.f_fiscal_qtr')(CAST(o.order_ts AS DATE))`. `IDENTIFIER(...)(args)` invocation was verified on the warehouse (`SELECT IDENTIFIER('abs')(-1)` → 1). `IDENTIFIER` as the name in `CREATE FUNCTION` was not exercised, because this analysis was read-only. If the implementing unit finds it unsupported, fall back to `EXECUTE IMMEDIATE` with the qualified name built from the parameters.
- Alternative: these are one-line, single-call-site functions, so inlining the expression in the unit is also bit-for-bit (verified identically). It also removes the cross-schema dependency. If inlined, keep the canonical text in §4 / `src/sql/shared/` so that both units use the same expression.

---

## 4. Shared inline macros (Redshift idioms)

These idioms need aggregate or window context, or column-level typing, so SQL UDFs cannot express them. Proposed home: **`src/sql/shared/macros.sql`**, a reference catalogue of canonical expression templates with a comment header per macro. Units copy the template inline with their own column expressions; nothing executes the file itself. `ci/classify_changes.py` `classify()` treats any path outside `src/sql/units/<unit>.sql`, `src/sql/units/<unit>/` and `resources/<unit>.job.yml` (and not under `tests/`, `docs/`, `.github/`, `README`) as shared. A change to `src/sql/shared/` therefore selects **all** registered units, which is the right blast radius for a shared definition. The macros reference no catalog or schema, so they are suffix-agnostic. Only table references use `IDENTIFIER(:catalog || '.' || :<layer>_schema || '.<t>')`.

| # | Macro (name) | Redshift idiom & semantics | Databricks template (verified result) | Used at |
| --- | --- | --- | --- | --- |
| M1 | `rpad_char(x, n)` | `CHAR(n)` is blank-padded on output. Comparisons and `GROUP BY` ignore trailing blanks. | `rpad(x, n, ' ')`, applied once at silver load to stay in STRING (customers/stores region; `customer_ltv` 0/0, `geo_rollup` 0/0, `customer_ltv` report 0/0) | `legacy/redshift/units/customer_ltv/etl.sql:10,18`; `legacy/redshift/units/customer_ltv/report.sql:2,8`; `legacy/redshift/units/geo_rollup/etl.sql:6-7,10,17`; `legacy/redshift/units/product_perf/etl.sql:9,14`; `legacy/redshift/units/store_weekly/report.sql:3,9` |
| M2 | `listagg_ordered(val, ord…, sep)` | `LISTAGG(x, ',') WITHIN GROUP (ORDER BY …)` skips NULLs. On a CHAR input each element **drops** its trailing pad (`"WEST,SOTH,NE"` in `golden/product_perf/product_perf.csv`). | `array_join(transform(array_sort(collect_list(struct(<rank>, rtrim(<val>) AS v))), x -> x.v), '<sep>')`, where `<rank>` = `ROW_NUMBER() OVER (… ORDER BY units DESC, region)` (`product_perf` 0/0). | `legacy/redshift/units/product_perf/etl.sql:18` |
| M3 | `redshift_avg_int(x)` | `AVG` over an integer column returns an integer, truncated toward zero. `AVG` ignores NULLs, and the result is NULL when every input is NULL. | `SUM(x) DIV NULLIF(COUNT(x), 0)`. If a DECIMAL column is required: `CAST(SUM(x) DIV NULLIF(COUNT(x), 0) AS DECIMAL(10,2))` (`shipping_sla` 71.00 not 71.99; `churn_flags` report 0/0; `rfm_segments` report 0/0) | `legacy/redshift/units/shipping_sla/etl.sql:9`; `legacy/redshift/units/churn_flags/report.sql:4`; `legacy/redshift/units/rfm_segments/report.sql:5` |
| M4 | `redshift_avg_dec2(x)` | `AVG` over `NUMERIC(p,2)` returns scale 2, truncated (not rounded). | `CAST(FLOOR(AVG(x), 2) AS DECIMAL(38,2))`. Plain `AVG` → DECIMAL(17,6) and rounds when cast: 669/1500 `aov` rows differ with rounding, 0 with FLOOR. Inputs are non-negative. | `legacy/redshift/units/customer_ltv/etl.sql:14`; `legacy/redshift/units/customer_ltv/report.sql:6`; `99_orchestration/exec_summary/etl.sql:14` |
| M5 | `redshift_int_div(a, b)` | `INT / INT` is integer division, truncating toward zero. Division by zero raises an error. | `a DIV b`. ANSI also raises DIVIDE_BY_ZERO. (`returns_rate` 0/0) | `legacy/redshift/units/returns_rate/etl.sql:8`; inside `f_fiscal_qtr` `legacy/redshift/00_foundation/03_udfs.sql:8` |
| M6 | `redshift_numeric_div(a, b, scale)` | `NUMERIC / NUMERIC` keeps a fixed result scale and truncates there. | Truncate to the observed result scale with `FLOOR(a/b, s)` (non-negative values). `returns_rate.return_pct`: `CAST(FLOOR(CAST(n AS DECIMAL(14,4)) / CAST(d AS DECIMAL(14,4)), 15) * 100 AS DECIMAL(38,15))` → `5.116959064327400`. `payment_mix.amount_share`: `CAST(FLOOR(SUM(amount) / SUM(SUM(amount)) OVER (), 4) AS DECIMAL(38,4))`. `exec_summary.avg_ship_hours`: `CAST(FLOOR(SUM(h * n) / SUM(n), 4) AS DECIMAL(38,4))`. (all 0/0) | `legacy/redshift/units/returns_rate/etl.sql:9-10`; `legacy/redshift/units/payment_mix/etl.sql:14`; `99_orchestration/exec_summary/etl.sql:15-18` |
| M7 | `ratio_to_report(x)` | `RATIO_TO_REPORT(x) OVER ()` on NUMERIC returns float8. It is computed as a NUMERIC quotient and then converted, and it is NULL on a zero total. | `CAST(try_divide(CAST(x AS DECIMAL(18,2)), CAST(SUM(x) OVER () AS DECIMAL(18,2))) AS DOUBLE)` (`category_mix` 0/0). A DOUBLE/DOUBLE quotient differs in the last ULP on 3/6 rows. | `legacy/redshift/units/category_mix/etl.sql:7` |
| M8 | `redshift_percentile_cont_dec2(x, p)` (also MEDIAN = p 0.5) | `MEDIAN` / `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY x)` over NUMERIC(38,2) interpolate linearly, ignore NULLs, and truncate to scale 2. | Per group: `rn = ROW_NUMBER() OVER (… ORDER BY x NULLS LAST)`, `n = COUNT(x)`, `pos = CAST(p*(n-1) AS DECIMAL(38,6))`, `lo = max(CASE WHEN rn = 1+FLOOR(pos) THEN x END)`, `hi = max(CASE WHEN rn = 2+FLOOR(pos) THEN x END)`. Result: `CAST(FLOOR(lo + (pos-FLOOR(pos)) * (coalesce(hi,lo) - lo), 2) AS DECIMAL(38,2))` (`promo_lift` 0/0). | `legacy/redshift/units/promo_lift/etl.sql:14-15` |
| M9 | `redshift_epoch_s(ts)` / `redshift_datediff_hour(a,b)` / `redshift_datediff_second(a,b)` | `DATEDIFF(hour, a, b)` counts hour **boundaries** crossed. `DATEDIFF(second, …)` counts second boundaries. Both are negative when b < a and NULL when either input is NULL. | `epoch_s(t) = datediff(CAST(t AS DATE), DATE'1970-01-01')*86400 + hour(t)*3600 + minute(t)*60 + floor(second(t))`. Hours: `(epoch_s(b) DIV 3600) - (epoch_s(a) DIV 3600)`. Seconds: `epoch_s(b) - epoch_s(a)`. Wall-clock on TIMESTAMP_NTZ, so it does not depend on the session time zone or DST. Do not use `unix_timestamp` or `timestampdiff`, which return the elapsed floor. (`shipping_sla` 0/0 apart from M3; `sessionization` 0/0) | `legacy/redshift/units/shipping_sla/etl.sql:9-11`; `legacy/redshift/units/sessionization/etl.sql:15-18` |
| M10 | `redshift_datediff_week(a,b)` | `DATEDIFF(week, a, b)` counts Monday-week boundaries. | `datediff(CAST(date_trunc('WEEK', b) AS DATE), CAST(date_trunc('WEEK', a) AS DATE)) DIV 7`. For `DATE '2025-01-01'` (Wednesday) the truncated week is `2024-12-30` (`store_weekly` 2120 rows 0/0). | `legacy/redshift/units/store_weekly/etl.sql:10-11`; `legacy/redshift/units/store_weekly/report.sql:4` |
| M11 | `redshift_datediff_month(a,b)` | `DATEDIFF(month, a, b)` counts month boundaries. | When both sides are month-truncated (as in legacy): `CAST(months_between(b, a) AS INT)`. In general: `(year(b)-year(a))*12 + month(b)-month(a)` (`cohort_retention` report 0/0) | `legacy/redshift/units/cohort_retention/etl.sql:21,26` |
| M12 | `redshift_datediff_day(a,b)` / `date_minus_date` | `DATEDIFF(day, a, b)` and `DATE - DATE` both return an INT day count. | `datediff(b, a)` (`rfm_segments` 0/0; `churn_flags` report 0/0) | `legacy/redshift/units/rfm_segments/etl.sql:10`; `legacy/redshift/units/churn_flags/etl.sql:39,42,43` |
| M13 | `trunc_date(ts)` | `TRUNC(ts)` / `ts::DATE` give the date part. `DATE_TRUNC('month'\|'week', ts)::DATE` gives the period start (weeks start Monday). | `CAST(ts AS DATE)`; `CAST(date_trunc('MONTH'\|'WEEK', ts) AS DATE)`; `DATEADD(day, 6, …)` → `date_add(d, 6)` | `legacy/redshift/units/daily_revenue/etl.sql:7`; `legacy/redshift/units/daily_revenue/report.sql:2`; `legacy/redshift/units/finance_export/etl.sql:5,10`; `legacy/redshift/units/store_weekly/etl.sql:8-9,16`; `legacy/redshift/units/cohort_retention/etl.sql:14,21`; `legacy/redshift/units/churn_flags/etl.sql:25`; `legacy/redshift/units/rfm_segments/etl.sql:10` |
| M14 | `fiscal_year(ts)` | `CASE WHEN EXTRACT(MONTH) >= 2 THEN year ELSE year-1 END` | `CASE WHEN month(ts) >= 2 THEN year(ts) ELSE year(ts) - 1 END` (`finance_monthly` 0/0) | `legacy/redshift/units/finance_export/etl.sql:6-9` |
| M15 | `fiscal_qtr(d)` | §3.1 | §3.1 | `legacy/redshift/units/finance_export/etl.sql:10` |
| M16 | `convert_tz_utc_to(tz, ts)` | `CONVERT_TIMEZONE('UTC', tz, ts)` on TIMESTAMP returns a TIMESTAMP. | `convert_timezone('UTC', tz, ts)` on TIMESTAMP_NTZ returns TIMESTAMP_NTZ, independent of the session (verified: `earliest_local_delivery_hour` 0 per carrier). `EXTRACT(HOUR …)::INT` → `CAST(hour(…) AS INT)` | `legacy/redshift/units/shipping_sla/etl.sql:13-14` |
| M17 | `nvl` / `nvl2` / `decode` | `NVL(a,b)`; `NVL2(x, nn, n)`; `DECODE(x, k1,v1, …, default)` (equality match, including NULL-to-NULL matching) | `coalesce(a,b)`; `nvl2(x, nn, n)`; `decode(x, k1, v1, …, default)` (or a CASE with explicit NULL matching) (`payment_mix` 0/0) | `legacy/redshift/units/payment_mix/etl.sql:4,5-10,11` |
| M18 | `line_net_revenue` | `oi.quantity * (oi.unit_price - oi.discount)` is INT × NUMERIC(12,2) → NUMERIC(…,2). `SUM` stays at scale 2. | Same expression on INT × DECIMAL(12,2), giving DECIMAL(23,2). Its SUM is DECIMAL(33,2), scale 2, so results are exact. Cast where legacy casts (`::NUMERIC(18,2)` at `legacy/redshift/units/product_perf/etl.sql:31`). | `legacy/redshift/units/daily_revenue/etl.sql:10`; `legacy/redshift/units/customer_ltv/etl.sql:13`; `legacy/redshift/units/geo_rollup/etl.sql:13`; `legacy/redshift/units/product_perf/etl.sql:31`; `legacy/redshift/units/store_weekly/etl.sql:13`; `legacy/redshift/units/category_mix/etl.sql:11`; `legacy/redshift/units/promo_lift/etl.sql:7`; `legacy/redshift/units/rfm_segments/etl.sql:12`; `legacy/redshift/units/finance_export/etl.sql:12` |
| M19 | `reporting_anchor` | Fixed as-of date `'2025-12-31'` | `DATE'2025-12-31'`, written as a literal, matching legacy. Do not use `current_date()`. | `legacy/redshift/units/churn_flags/etl.sql:39,42,43`; `legacy/redshift/units/rfm_segments/etl.sql:10`; `legacy/redshift/units/inventory_snapshot/etl.sql:41`; `99_orchestration/exec_summary/etl.sql:5-6` |
| M20 | `redshift_null_order` | Redshift sorts NULLs as the largest value: `NULLS LAST` for ASC, `NULLS FIRST` for DESC. Databricks does the opposite. | Always write window `ORDER BY` NULL placement explicitly, e.g. `NTILE(5) OVER (ORDER BY recency_days ASC NULLS LAST, customer_id)` (146 customers have NULL `recency_days`; `rfm_segments` 1500 rows 0/0). | `legacy/redshift/units/rfm_segments/etl.sql:23-25`; also LAG/ROW_NUMBER orderings in `legacy/redshift/units/sessionization/etl.sql:13-17,29-31`, `legacy/redshift/units/product_perf/etl.sql:21-22` (no NULLs in D0) |
| M21 | `super_unnest(payload, path)` | PartiQL `FROM t, t.payload.touches tc` (inner unnest; rows with an empty or missing array drop out) plus `tc.field::VARCHAR(16)` | `FROM t, LATERAL variant_explode(parse_json(t.payload):touches) tc`, then `CAST(tc.value:campaign_id AS STRING)` (`attribution` 100 rows 0/0) | `legacy/redshift/units/attribution/etl.sql:4-5,8-9` |
| M22 | `round_half_up_dec(x, 2)` | `ROUND(100.0 * a / b, 2)` (NUMERIC) | `CAST(ROUND(100.0 * a / b, 2) AS DECIMAL(38,2))` (`cohort_retention` report 65 rows 0/0) | `legacy/redshift/units/cohort_retention/report.sql:6` |

Units that use none of the macros above beyond plain SQL: `basket_affinity` (self-join + HAVING), `inventory_snapshot` (aside from M19; its plpgsql procedure ports as a `BEGIN … END` block, verified 300 rows 0/0), and `attribution` (aside from M21).

## 5. Recommended placement summary (migration repo)

| Artifact | Path | Referenced as |
| --- | --- | --- |
| Foundation DDL + load + UDFs | `src/sql/units/foundation.sql` (+ `resources/foundation.job.yml`, registry key `foundation`, `outputs` = the 10 `silver.*`, `owns` = the 10 `bronze.*`) | Job parameters `catalog`, `bronze_schema`, `silver_schema`, `golden_path` → `IDENTIFIER(:catalog || '.' || :silver_schema || '.<t>')` |
| UDFs `f_fiscal_qtr`, `f_clean_phone` | created by `foundation.sql` in `${catalog}.${silver_schema}` | `IDENTIFIER(:catalog || '.' || :silver_schema || '.f_fiscal_qtr')(…)`; callers `depends_on: ["foundation"]` |
| Shared macro catalogue (M1–M22) | `src/sql/shared/macros.sql` (reference templates, not executed) | Copied inline. A change selects all units via `ci/classify_changes.py`. |
| This document | `docs/discovery/shared_macros.md` | — |
