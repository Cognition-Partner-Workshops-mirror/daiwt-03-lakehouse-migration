# Orchestration mapping: Redshift nightly refresh -> Lakeflow Jobs (DAIWT-03)

Scope: wave 2 unit `orchestration` plus every scheduled or off-workflow job in the
legacy estate. The legacy repo is `daiwt-03-redshift` (`main` @ `1bee48a`), cited as `L:path:line`.
The migration repo is `daiwt-03-lakehouse-migration` (`main` @ `80095cd`), cited as `M:path:line`.

## 1. Legacy scheduling inventory

| # | Legacy artefact | Kind | Cadence | Evidence |
|---|---|---|---|---|
| 1 | `nightly_mart_refresh` | Scheduler job spec (YAML, step DAG) | `0 2 * * *`, `UTC` | L:legacy/redshift/99_orchestration/refresh_schedule.yaml:3-5 |
| 2 | `exec_summary` ETL | Final step of #1 | nightly (in #1) | L:refresh_schedule.yaml:34-36; L:legacy/redshift/99_orchestration/exec_summary/etl.sql:1-2 |
| 3 | `exec_summary` BI report | Report query (not scheduled) | on read | L:legacy/redshift/99_orchestration/exec_summary/report.sql:1-5 |
| 4 | `finance_export` UNLOAD to S3 | Export step of #1 | listed in nightly #1; header calls it "Monthly" | L:refresh_schedule.yaml:37-39; L:legacy/redshift/units/finance_export/export.sql:1-8 |
| 5 | Makefile targets `setup`, `reset`, `legacy-all`, `capture-golden`, `seed`, `db-setup`, `validate`, `validate-all`, `check` | Operator/manual commands | manual only | L:Makefile:1-39 |
| 6 | `tools/legacy_redshift.py` `setup/build/capture/all` | Operator runner | manual only | L:tools/legacy_redshift.py:1-11, 278-294 |
| 7 | `tools/source_connection.py`, `tools/provision_redshift.py`, `tools/databricks_setup.py`, `tools/check_manifest.py` | Operator/provisioning/static checks | manual only | L:tools/source_connection.py:1-27; L:tools/provision_redshift.py:1; L:tools/databricks_setup.py:1; L:tools/check_manifest.py:1-8 |

Absence checks:
- The repo has no crontab, no CI scheduler, no Airflow/Step Functions definitions, and no `schedule:` key outside `refresh_schedule.yaml`. A grep for `cron|schedul|cadence|hourly|unload|s3://|refresh` matches only the files above.
- The README calls the schedule "a specification, not an installed scheduler" (L:README.md:17-21). It also says "no ... recurring refresh jobs or export buckets created here" (L:README.md:80).
- The UNLOAD is listed in the finance_export `capture_skip` (L:.migration/units.yaml:289). The README says it "is not run by setup: no export destination is provisioned" (L:README.md:20-21).
- The refresh schedule is listed in the orchestration `capture_skip` (L:.migration/units.yaml:323). It has no golden.

### 1.1 `nightly_mart_refresh` step graph (legacy)

| Step | Runs | depends_on | Evidence |
|---|---|---|---|
| `load_core` | `tools/legacy_redshift.py setup --ddl-only` | - | refresh_schedule.yaml:7-9 |
| `wave_1a` | 5 unit `etl.sql`: daily_revenue, customer_ltv, geo_rollup, churn_flags, product_perf | load_core | refresh_schedule.yaml:10-17 |
| `wave_1b` | 13 unit `etl.sql`: store_weekly, category_mix, basket_affinity, sessionization, shipping_sla, rfm_segments, promo_lift, payment_mix, returns_rate, attribution, inventory_snapshot, finance_export, cohort_retention | load_core | refresh_schedule.yaml:18-33 |
| `exec_summary` | `99_orchestration/exec_summary/etl.sql` | wave_1a, wave_1b | refresh_schedule.yaml:34-36 |
| `finance_export` | `units/finance_export/export.sql` (UNLOAD) | wave_1b | refresh_schedule.yaml:37-39 |

Semantics the target must keep:
- **Steps are group gates.** `exec_summary` waits for all 18 marts, not only the four it reads (refresh_schedule.yaml:36). The UNLOAD waits for all 13 wave-1b marts (refresh_schedule.yaml:39).
- **Wave widths are 1 / 5 / 13 / 1** (L:.migration/units.yaml:2-8). Within a wave, units are independent: each `reads` list contains only `silver.*` tables (units.yaml `reads:` per unit).
- **`load_core` is the foundation.** In the legacy runner, setup drops and recreates `core` and `mart`, runs the foundation DDL/UDFs and loads the seed CSVs (L:tools/legacy_redshift.py:120-160). The target equivalent is unit `foundation`: it reads golden inputs `inputs/D0/core.*.csv` and writes `bronze.*` and `silver.*` (L:.migration/units.yaml:10-20).
- **Every legacy unit `etl.sql` is a full rebuild** (`DROP TABLE IF EXISTS` + `CREATE TABLE AS`), for example L:exec_summary/etl.sql:3-4 and L:units/finance_export/etl.sql:3-4. The target maps this to `CREATE OR REPLACE TABLE`, so each task is idempotent on re-run.
- **Execution order in the legacy operator** is a flattened wave order (L:tools/legacy_redshift.py:163-182). It runs only `etl.sql` files and skips `capture_skip` (the UNLOAD).
- **Deterministic anchor.** `exec_summary` hard-codes `as_of_date = DATE '2025-12-31'` and `snapshot_label = 'as_of_2025-12-31'` (L:exec_summary/etl.sql:5-6). These do not depend on schedule time, so scheduled and ad-hoc runs give identical output.

### 1.2 `exec_summary` semantics (target must mirror)

- Output `gold.exec_summary` is a single row. It is built from 4 CROSS JOINed scalar subqueries (L:exec_summary/etl.sql:12-18):
  - `total_revenue = SUM(revenue)`, `total_orders = SUM(order_count)` from `daily_revenue` (lines 12-13).
  - `avg_customer_ltv = AVG(ltv)` over `customer_ltv`, with `ltv` as NUMERIC(…,2) (line 14). Redshift NUMERIC AVG keeps the input scale (truncation); golden value `7029.21`.
  - `overall_return_pct = SUM(returned_qty)::NUMERIC(14,4) / SUM(sold_qty)::NUMERIC(14,4) * 100` from `returns_rate` (lines 15-16). Golden value `5.013772053897100` (scale 15).
  - `avg_ship_hours = SUM(avg_hours_to_deliver * delivered) / SUM(delivered)` from `shipping_sla` (lines 17-18). The inputs are the stored per-carrier `avg_hours_to_deliver` NUMERIC(10,2) values (L:units/shipping_sla/etl.sql:9), not raw shipments. Golden value `71.2551` (scale 4).
- Golden: `golden/orchestration/exec_summary.csv` and `report.csv`, both 1 row, key `snapshot_label` (L:.migration/units.yaml:324-329). Column families: string, date, decimal, int, decimal, decimal, decimal (`exec_summary.meta.json`).
- Data reads are `gold.daily_revenue`, `gold.customer_ltv`, `gold.returns_rate`, `gold.shipping_sla` (L:.migration/units.yaml:319).
- The report is a straight projection ordered by `snapshot_label` (L:exec_summary/report.sql:2-5). The contract targets it as table `gold.report_orchestration` (M:src/parity/contract.json:1604-1607). `gold.exec_summary` is at M:src/parity/contract.json:1562-1565.

### 1.3 UNLOAD export semantics (target must mirror)

`UNLOAD ('SELECT * FROM mart.finance_monthly ORDER BY month') TO 's3://<bucket>/finance_export/monthly/' IAM_ROLE '<role-arn>' PARALLEL OFF CSV HEADER` (L:units/finance_export/export.sql:3-8):
- Source is `mart.finance_monthly`, i.e. target `gold.finance_monthly` (L:.migration/units.yaml:286, 291-292). All columns, ordered by `month`.
- The format is CSV with a header row and serial output (`PARALLEL OFF`), so one ordered file for this data size.
- Bucket and role are placeholders: no destination exists (L:README.md:20-21, 80). The UNLOAD has no golden and is not part of parity (`capture_skip`, L:.migration/units.yaml:289).

## 2. Current state of the migration repo (`main` @ 80095cd)

| Item | State | Evidence |
|---|---|---|
| `resources/*.yml` | **Missing.** No `resources/` dir and no `include:` in `databricks.yml` | M:databricks.yml:1-61 |
| Bundle jobs | **None.** The bundle declares only dev `schemas` (bronze/silver/gold `_${schema_suffix}`) | M:databricks.yml:32-45 |
| Unit registry | `{}` (0 units) | M:src/sql/units/registry.json:1; M:docs/registry.md:3 |
| Registry entry shape | Exactly `job`, `outputs`, `owns`, `depends_on`. Job keys are unique. Tables match `(bronze\|silver\|gold)\.[a-z][a-z0-9_]*` | M:ci/registry.py:42-75 |
| Unit runner | `databricks bundle run -t <target> --var schema_suffix=<s> --params drop=<D> <job>`, one job per unit, in topo order | M:ci/run_units.py:16-31 |
| Job params | Unit jobs receive only `drop` | M:README.md:133-134; M:ci/run_units.py:16 |
| Job naming | `${var.job_name_prefix}<unit>`: dev `[pr_<n>] <unit>`, prod `<unit>` | M:README.md:85-87; M:databricks.yml:19-21, 58 |
| Dev schedule behaviour | `targets.dev.presets.trigger_pause_status: PAUSED`. Dev does not set `mode: development` | M:databricks.yml:24-27 |
| Prod mode / permissions | `mode: production`; top-level `permissions`: deploying SP `CAN_MANAGE`, group `users` `CAN_VIEW` | M:databricks.yml:46-52; M:README.md:26-28 |
| Warehouse | `6dc4b80538621b7b` (var `warehouse_id`) | M:databricks.yml:15-16 |
| Prod schemas | Owned by Terraform (`bronze`, `silver`, `gold`, `landing`), not the bundle | M:README.md:26-27 |
| Prod volumes | `landing.bronze_landing`, `landing.golden` only. `gold` has no volumes | Databricks UC listing (read-only) |
| Prod grants | Devin-CI has `ALL_PRIVILEGES` on prod non-landing schemas and `USE_CATALOG` on the catalog | dbx-data-platform-infra `daiwt-03-demo/platform/databricks/main.tf:73-77, 97-103` |
| CI workflows | `pr.yml` (validate only, no deploy), `deploy-prod.yml` (deploy + run all registered units per drop + parity), `reset.yml`, `dev-sweep.yml`. None is scheduled | M:.github/workflows/*.yml |
| Cleanup | Dev: drops marker-commented `*_pr_<n>` schemas + `bundle destroy`. Prod: `bundle destroy` + drop registry tables. Landing is never cleaned | M:ci/reset.sh:3-9; M:ci/cleanup.py:17-24, 62-76; M:README.md:111-118 |

## 3. Target design

### 3.1 Job/task resources that must exist

Two layers are needed:
- **(a) One bundle job per registry unit.** CI requires this (`run_units.py` runs registry `job` keys).
- **(b) One scheduled orchestration job** that reproduces `nightly_mart_refresh` with `run_job_task`s pointing at the (a) jobs. This avoids duplicating unit SQL.

| Resource key (`resources.jobs.*`) | Name | Tasks | Registry entry (`depends_on`) | Contract outputs |
|---|---|---|---|---|
| `foundation` | `${var.job_name_prefix}foundation` | `foundation` (bronze ingest from `golden/inputs/<drop>/core.*.csv`, then typed silver) | `[]` | 10 `silver.*` (owns 10 `bronze.*`) |
| `daily_revenue` … `product_perf` (5) | `${var.job_name_prefix}<unit>` | `etl`, then `report` | `[foundation]` | `gold.<table>`, `gold.report_<unit>` |
| `store_weekly` … `cohort_retention` (13) | `${var.job_name_prefix}<unit>` | `etl`, then `report` (finance_export: plus `export`, see 3.3) | `[foundation]` | `gold.<table>`, `gold.report_<unit>` |
| `orchestration` | `${var.job_name_prefix}orchestration` | `exec_summary`, then `exec_summary_report` | `[daily_revenue, customer_ltv, returns_rate, shipping_sla]` (data deps, L:.migration/units.yaml:319) | `gold.exec_summary`, `gold.report_orchestration` |
| `nightly_mart_refresh` | `${var.job_name_prefix}nightly_mart_refresh` | DAG in 3.2 (`run_job_task` only) | **not registered** (owns no tables) | none |

Notes:
- Registry job keys must equal the legacy unit names, or contract outputs SKIP (contract `unit` field, e.g. M:src/parity/contract.json:1564).
- Every unit job declares job parameter `drop` (default `D0`) and passes catalog/layer schemas from bundle variables (M:README.md:85-87).
- `nightly_mart_refresh` must not be in `registry.json`. If it were, `run_units.py` would execute it in addition to each unit, and the units would run twice.

### 3.2 `nightly_mart_refresh` task DAG (mirrors refresh_schedule.yaml)

| task_key | Type | depends_on | Legacy step |
|---|---|---|---|
| `load_core` | `run_job_task: ${resources.jobs.foundation.id}` | - | load_core (yaml:7-9) |
| `daily_revenue`, `customer_ltv`, `geo_rollup`, `churn_flags`, `product_perf` | `run_job_task` -> unit job | `load_core` | wave_1a (yaml:10-17) |
| `store_weekly`, `category_mix`, `basket_affinity`, `sessionization`, `shipping_sla`, `rfm_segments`, `promo_lift`, `payment_mix`, `returns_rate`, `attribution`, `inventory_snapshot`, `finance_export`, `cohort_retention` | `run_job_task` -> unit job | `load_core` | wave_1b (yaml:18-33) |
| `wave_1a` | `condition_task` gate (or omit; see below) | 5 wave-1a tasks | group gate |
| `wave_1b` | `condition_task` gate | 13 wave-1b tasks | group gate |
| `exec_summary` | `run_job_task` -> `orchestration` | `wave_1a`, `wave_1b` | exec_summary (yaml:34-36) |
| `finance_export_unload` | `run_job_task` -> `finance_export_unload` job (3.3), or the export task inside `finance_export` | `wave_1b` | finance_export (yaml:37-39) |

- Gates: a `condition_task` (`"1" == "1"`) with default `run_if: ALL_SUCCESS` reproduces the legacy group dependency exactly. The alternative is to list the 18 / 13 task keys directly in `depends_on`; the semantics are the same.
- Job parameter `drop` (default `D0`) is forwarded to each child via `run_job_task.job_parameters: {drop: "{{job.parameters.drop}}"}`.
- `max_concurrent_runs: 1` matches a single nightly instance. Wave widths are 5 / 13, so up to 13 child runs execute concurrently on warehouse `6dc4b80538621b7b`.
- Retries: the legacy spec defines none (refresh_schedule.yaml:6-39). Mirror with `max_retries: 0`. Optionally set `max_retries: 1` / `min_retry_interval_millis: 60000` on unit tasks: every unit is a full rebuild (`CREATE OR REPLACE`), so a retry is idempotent.
- Timeout: none in the legacy spec. Recommended `timeout_seconds` on the job to bound a stuck run (implementation choice).

### 3.3 Re-homed off-warehouse job: finance UNLOAD -> UC volume

| Legacy | Target |
|---|---|
| `UNLOAD ... TO 's3://<bucket>/finance_export/monthly/' IAM_ROLE ...` (export.sql:3-5) | Write to a UC volume `/Volumes/${var.catalog}/${var.gold_schema}/exports/finance_export/monthly/` |
| `SELECT * FROM mart.finance_monthly ORDER BY month` | `SELECT * FROM ${catalog}.${gold}.finance_monthly ORDER BY month` |
| `PARALLEL OFF CSV HEADER` (export.sql:6-8) | One CSV file with a header row. Use a notebook/Python task that collects the ordered result and writes one file (`dbutils.fs.put` / Files API), or `INSERT OVERWRITE DIRECTORY ... USING CSV OPTIONS (header true)` with `coalesce(1)` |
| IAM role auth | UC volume privileges (`WRITE_VOLUME`) for the job's run-as principal |

Required resources:
- **Volume** `exports` in the gold schema, as a bundle `resources.volumes.exports` (`catalog_name: ${var.catalog}`, `schema_name: ${var.gold_schema}`, `volume_type: MANAGED`).
  - In dev the volume lives inside bundle-owned `gold_pr_<n>`.
  - In prod, gold is Terraform-owned but Devin-CI holds `ALL_PRIVILEGES` on it (infra main.tf:97-103), so the bundle can create the volume there. The alternative is to add it to Terraform next to `landing` volumes.
- **Job/task.** Either:
  - a task `export` inside the `finance_export` unit job, after `etl`; or
  - a separate job `finance_export_unload` run by `nightly_mart_refresh.finance_export_unload` after `wave_1b`, matching yaml:37-39.
  - The separate job keeps unit CI runs free of the export side effect. It must not be registered (it owns no tables and has no golden).
- **Cadence.** The legacy spec puts the export inside the nightly job (yaml:37-39), while the SQL header labels it "Monthly" (export.sql:1). Mirroring the spec means running it nightly in `nightly_mart_refresh`. A monthly-only cadence would instead be a separate scheduled job, `quartz_cron_expression: "0 0 2 1 * ?"`, `timezone_id: UTC`. The nightly schedule is the legacy cadence; a monthly schedule is a separate deployment configuration.
- **Verification.** The export has no golden (`capture_skip`). Check it by comparing the exported CSV to `gold.finance_monthly` row-for-row (same columns and order) and asserting a header row plus one file.

### 3.4 Schedule translation

| Legacy (yaml:4-5) | Lakeflow `schedule` |
|---|---|
| `schedule: "0 2 * * *"` (5-field cron: min hour dom mon dow) | `quartz_cron_expression: "0 0 2 * * ?"` (Quartz: sec min hour dom mon dow; `?` required in dom or dow) |
| `timezone: UTC` | `timezone_id: "UTC"` |
| (implicit: active) | `pause_status`: see below |

Translation rules for any other Unix cron: prepend a seconds field `0`, and replace `*` with `?` in exactly one of dom/dow.

Optional monthly export cron: `0 2 1 * *` translates to `0 0 2 1 * ?`.

Timezone note: the schedule's timezone is independent of data timezone semantics. `shipping_sla` converts UTC to `America/Los_Angeles` inside SQL (L:units/shipping_sla/etl.sql:13-14), and all outputs are anchored to the literal `2025-12-31`. The run time does not affect results.

### 3.5 Dev pause behaviour and target overrides

- **Dev:** `presets.trigger_pause_status: PAUSED` already pauses every schedule and trigger in dev (M:databricks.yml:26-27). Each `pr_<n>` deploy creates `[pr_<n>] nightly_mart_refresh` paused, so concurrent PR deployments never run on a timer. The job is still runnable with `databricks bundle run nightly_mart_refresh`.
- **Live dev schedule (only if explicitly wanted):** the job-level override `targets.dev.resources.jobs.nightly_mart_refresh.schedule.pause_status: UNPAUSED` takes precedence over the preset for that job. Dev does not use `mode: development`, so the preset is the only pause mechanism.
- **Prod:** `mode: production` applies no pause preset. Set `schedule.pause_status: UNPAUSED` explicitly on `nightly_mart_refresh` so the nightly 02:00 UTC run is active after `deploy-prod.yml`.
  - Unit jobs and `orchestration` have no schedule. Only `nightly_mart_refresh` (and an optional monthly export job) carry a schedule.
  - `deploy-prod.yml` keeps running units directly through `run_units.py` for parity (M:.github/workflows/deploy-prod.yml:29-38). The schedule adds a recurring run; it does not replace CI parity.
- **Reset/cleanup:** `bundle destroy` already removes every bundle job, including the scheduler job, in both dev and prod (M:ci/reset.sh:3-9; M:ci/cleanup.py:72-76).
  - Prod cleanup drops only registry tables. The `exports` volume is not covered by table cleanup, because `ci/cleanup.py` enumerates `information_schema.tables`.
  - If it is a bundle resource, `bundle destroy` removes it. If it is Terraform-owned, it persists, like `landing`.

### 3.6 Job permissions and run-as conventions

- Prod: inherit top-level bundle `permissions`, i.e. deploying SP (Devin-CI) `CAN_MANAGE` and `users` `CAN_VIEW` (M:databricks.yml:48-52). Do not add per-job `permissions` blocks. `bundle validate --strict -t prod` passes with the top-level block (M:.github/workflows/deploy-prod.yml:27).
- Dev: no permissions block. The builder identity that deploys `pr_<n>` owns the jobs, and cleanup must run as that same principal (M:README.md:116-117).
- Run-as: default (deployer). In prod this is Devin-CI, which has `ALL_PRIVILEGES` on prod `bronze/silver/gold` and read access on `landing.golden` (infra main.tf:73-77, 97-103, 140-141). This covers writing `gold.*` and creating/writing the `exports` volume.
- Names: `${var.job_name_prefix}<key>` for every job, including `nightly_mart_refresh` and `finance_export_unload` (M:README.md:86-87).
- Environment: GitHub jobs must declare `environment: dev|prod` for OIDC federation (M:README.md:35). Scheduled runs execute inside Databricks and need no GitHub environment.

## 4. Checklist of resources to add

1. `databricks.yml`: `include: [resources/*.yml]`.
2. `resources/foundation.job.yml`, plus 18 `resources/<unit>.job.yml`, plus `resources/orchestration.job.yml` (unit jobs with `drop` param and `${var.job_name_prefix}` names).
3. `resources/nightly_mart_refresh.job.yml`:
   - `run_job_task` DAG from 3.2, with `max_concurrent_runs: 1`;
   - `schedule: {quartz_cron_expression: "0 0 2 * * ?", timezone_id: UTC}`;
   - prod `pause_status: UNPAUSED` (dev stays paused via preset).
4. `resources/finance_export_unload.job.yml` (or an `export` task in `finance_export`) and `resources/exports.volume.yml` (`gold.exports`).
5. `src/sql/units/registry.json`: 20 entries (foundation, 18 units, orchestration). Exclude `nightly_mart_refresh` and `finance_export_unload`.
6. Offline tests:
   - the registry graph matches `units.yaml` waves;
   - the scheduler DAG task keys and depends_on match refresh_schedule.yaml (5 steps, 18 unit tasks);
   - the Quartz expression and timezone are pinned.
