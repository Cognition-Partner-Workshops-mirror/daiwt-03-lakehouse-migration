# Silver Lakeflow scaffold

`silver_pipeline` depends on `silver_asof`, which brings `bronze_landing`.
Builders add only their own unit directory; no shared registration list changes.
`silver_resources.py` discovers sorted `silver_*/*.pipeline.sql`, excluding this
directory, and generates only the pipeline resource. Databricks rejects filtered
library globs, so discovery emits one exact file library per entity. The private
`scaffold_ready` MV keeps an entity-free deployment runnable without publishing a
Silver entity table. It is not a parity output or a cleanup target.

Use CLI 1.25.0 and install `requirements-dev.txt` into the active Python environment
(locally: `python -m venv .venv`, `source .venv/bin/activate`, then
`pip install -r requirements-dev.txt`). Python bundle resources use that interpreter;
there is no machine-specific virtualenv path in the bundle. Run bundle commands
from the repository root; `ci/dev_verify.sh` anchors itself there.

The job fully refreshes the pipeline, then runs the deployed parity harness with
`--layer silver`, the job drop, target catalog and suffix. The harness discovers
deployed unit metadata, compares only registered Silver outputs, and exits nonzero
on any FAIL. Unregistered outputs SKIP. Default harness behavior is unchanged.
Pipeline task parameters forward the job's `drop` (default D0).
Use `:drop` in pipeline SQL: runtime pipeline parameters do not override the
static `${drop}` Spark configuration substitution. The configuration retains a
D0 default, but named binding is required to honor the job's selected drop.

## Entity directory template

For `silver_<entity>`, add these four files. The explicit `silver_asof` dependency
also preserves its documented builder contract; dependency expansion deduplicates
the transitive edge. Classify/select/topological ordering require no changes.

`unit.json`:

```json
{"job":"silver_<entity>","legacy_unit":"foundation","outputs":["silver.<entity>"],"owns":["silver.<entity>_quarantine"],"depends_on":["silver_pipeline","silver_asof"]}
```

`<entity>.pipeline.sql` (replace names, columns and key predicate; use the exact
golden column names, types and order from target_model.md §3 and contract.json):

```sql
CREATE TEMPORARY VIEW <entity>_candidates AS
SELECT * FROM ${catalog}.${silver_schema}.asof_<entity>(:drop)
UNION ALL
SELECT <explicitly typed synthetic row with a NULL key>
WHERE '${silver_bad_rows}' = 'true';

CREATE OR REFRESH MATERIALIZED VIEW <entity> (
  CONSTRAINT valid_key EXPECT (<key> IS NOT NULL) ON VIOLATION DROP ROW
)
AS SELECT <ordered golden columns> FROM <entity>_candidates;

CREATE OR REFRESH MATERIALIZED VIEW <entity>_quarantine AS
SELECT *, 'null key' AS reason FROM <entity>_candidates WHERE <key> IS NULL;
```

Use only source rules (the keys are NOT NULL); do not invent rules on nullable
business columns. For additional expectations, quarantine the union of violations,
including NULL/unknown predicates (`NOT COALESCE(<predicate>, false)`), and provide
a reason. Keep synthetic values typed so UNION ALL cannot widen golden types.
MVs with TIMESTAMP_NTZ columns (including quarantine) require
`TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')` before `AS`.
Never add diagnostic columns to the golden-facing MV.

`silver_<entity>.job.yml`:

```yaml
resources:
  jobs:
    silver_<entity>:
      name: ${var.job_name_prefix}silver_<entity>
      parameters:
        - name: drop
          default: D0
      tags:
        environment: ${bundle.target}
      tasks:
        - task_key: self_check
          sql_task:
            warehouse_id: ${var.warehouse_id}
            file:
              path: ./self_check.sql
              source: WORKSPACE
            parameters:
              catalog: ${var.catalog}
              silver_schema: ${var.silver_schema}
              drop: "{{job.parameters.drop}}"
              silver_bad_rows: ${var.silver_bad_rows}
```

`self_check.sql`:

```sql
SELECT CASE WHEN :silver_bad_rows = 'true' OR count(*) = 0 THEN true
  ELSE raise_error('quarantine is not empty') END
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.<entity>_quarantine');

SELECT CASE WHEN
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.<entity>')) =
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_<entity>')(:drop))
  THEN true ELSE raise_error('asof row count mismatch') END;
```

Builder order is bronze_landing → silver_asof → silver_pipeline (refresh + verify)
→ entity self-check jobs → final parity. `silver_bad_rows` is a DEV-ONLY manual
demo, default `"false"`; prod pins `"false"`. Do not enable it in dev_verify or prod.
Manual dev demos may deploy with `--var silver_bad_rows=true`; only quarantine
gains rows, while filtered entity parity must still PASS.
