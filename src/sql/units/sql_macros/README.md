# Foundation SQL functions

The `sql_macros` job creates deterministic Unity Catalog SQL functions in
`${var.catalog}.${var.silver_schema}` (dev `silver_pr_<n>`, prod `silver`).
Its second SQL-file task self-checks the functions and raises an error on drift.
Both tasks use the bundle SQL warehouse, inherit bundle target permissions, and
accept the standard catalog/layer schema parameters. The job accepts `drop`
(default `D0`); these drop-independent functions read no input tables.

| Function | Signature | Semantics |
| --- | --- | --- |
| `f_fiscal_qtr` | `(d DATE) RETURNS STRING` | `'Q'` concatenated with `(((month(d) + 9) % 12) DIV 3) + 1`; integer division, NULL → NULL |
| `f_clean_phone` | `(p STRING) RETURNS STRING` | Remove every character except ASCII `0`–`9`; NULL → NULL, empty or punctuation-only → empty |

The fiscal formula deliberately follows the source **arithmetic**, not its
February-start comment. January through December return:
`Q4, Q4, Q1, Q1, Q1, Q2, Q2, Q2, Q3, Q3, Q3, Q4`.
Phone punctuation, whitespace and letters are removed; extension digits remain.
The DATE and STRING arguments fit `finance_export`'s date expression and
`customer_ltv`'s phone string respectively.

## Calling from Silver or Gold SQL-file tasks

Declare `depends_on: [sql_macros]` in the consuming unit's `unit.json`, then pass
`catalog: ${var.catalog}` and `silver_schema: ${var.silver_schema}` in its
`sql_task.parameters` (alongside the usual layer parameters). Call the function
with the **entire three-part function name** inside `IDENTIFIER`:

```sql
SELECT IDENTIFIER(:catalog || '.' || :silver_schema || '.f_fiscal_qtr')(d) AS fiscal_qtr,
       IDENTIFIER(:catalog || '.' || :silver_schema || '.f_clean_phone')(phone) AS clean_phone
FROM source_rows;
```

This does not depend on a task's current catalog/schema or a shared session.
The same syntax is used for `CREATE OR REPLACE FUNCTION` and in `self_check.sql`.
It was executed with SQL Statements API named parameters on warehouse
`6dc4b80538621b7b`, using `catalog=devin_dev` and
`silver_schema=d03_macros_scratch_1794327571`. Both creation statements and both
self-check statements succeeded. Calls for `DATE '2025-02-01'`,
`DATE '2025-03-01'` and `'+1 (212) 555-0199'` returned
`Q4`, `Q1`, and `12125550199`. The scratch schema was dropped afterwards;
no bundle deployment or writes to migration catalogs were used for this proof.
