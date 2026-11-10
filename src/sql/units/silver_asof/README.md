# Silver AS-OF helpers

`silver_asof` depends on `bronze_landing`. It creates functions, **not silver
entity tables**, in `${catalog}.${silver_schema}`. The SQL-file job creates the
functions and then checks them for its `drop` parameter (default `D0`). Permissions
and execution identity are inherited from the bundle.

## Functions and snapshot semantics

* `drop_seq(d STRING) RETURNS INT` is deterministic: `D0` → `0`, `D12` → `12`.
  Only uppercase `D` followed by ASCII digits is valid. Leading zeroes are
  accepted (`D01` → `1`). NULL, empty, whitespace, signs, suffixes and values
  outside the nonnegative INT range return NULL; nothing is trimmed.
* `resolve_drop(as_of_drop STRING) RETURNS STRING` is the shared resolver used
  by every table function. It returns the effective globally loaded drop label
  or NULL. Unlike `drop_seq`, this helper reads bronze data and is not deterministic.
* `asof_customers(as_of_drop STRING)`
* `asof_stores(as_of_drop STRING)`
* `asof_products(as_of_drop STRING)`
* `asof_orders(as_of_drop STRING)`
* `asof_order_items(as_of_drop STRING)`
* `asof_payments(as_of_drop STRING)`
* `asof_returns(as_of_drop STRING)`
* `asof_shipments(as_of_drop STRING)`
* `asof_web_events(as_of_drop STRING)`
* `asof_campaign_touches(as_of_drop STRING)`

Every table function returns its bronze table's business columns in the same
order and types, without `_drop` or `_loaded_at`. Values are projected unchanged.
Resolution is **global across all ten bronze tables**: a drop is loaded if any
table contains a row for it. The shared resolver chooses the greatest valid
numeric drop sequence at or before the requested sequence. Every table function
returns only rows with that exact `_drop`, including an empty result when that
table has no rows in the effective drop. It never falls back per table.
This is a full snapshot, not a union of earlier snapshots or a per-key merge.
Numeric ordering means `D10` follows `D2`, regardless of load timestamps. If two
labels have the same sequence, choose the most recently loaded one using
`max(_loaded_at)`, then the descending label to break any remaining tie.

Invalid/NULL requests or no eligible loaded rows produce an empty result with the
correct business schema. Invalid bronze labels are ignored. A newer drop with
an empty table supersedes that table's earlier nonempty snapshot, as long as any
of the other nine tables contains rows for the newer drop. A drop empty across
all ten tables has no lineage marker; distinguishing that from an unloaded drop
would require a separate load ledger. Call helpers only after the entire bronze
load job succeeds, not during a partial or failed load.

The DDL uses `EXECUTE IMMEDIATE` with backtick-escaped catalog/schema identifiers
to embed fully qualified bronze references at creation time. It does not depend
on the caller's current catalog/schema or leave parameter markers in stored
function bodies. Sequence values are projected before sorting because warehouse
SQL UDF calls directly in `ORDER BY` are not supported.

## Builder calls

SQL-file task parameters should include `catalog`, `silver_schema`, `drop` and
the target layer schema. The exact parameterized call syntax is:

```sql
SELECT IDENTIFIER(:catalog || '.' || :silver_schema || '.drop_seq')(:drop);

SELECT *
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_customers')(:drop);
```

An illustrative silver entity CTAS (owned by its own downstream unit):

```sql
CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :silver_schema || '.customers')
USING DELTA
AS SELECT *
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_customers')(:drop);
```

Downstream units should declare `depends_on: ["silver_asof"]`. Registry expansion
then runs `bronze_landing` before this helper unit. Call functions with the
explicit job drop; do not choose snapshots by lexicographic label or wall-clock
load time.

## Checks

The self-check validates scalar edge cases and compares all ten function row
counts against the independently resolved global bronze drop. Unity Catalog
`information_schema.columns` and `routine_columns` verify ordered business-column
names **and types**, including when results are empty. Any mismatch raises an
error.

Warehouse proof uses `6dc4b80538621b7b` and isolated bronze/silver proof schemas
in `daiwt_03_mig_dev`. It reads the golden D0 volume read-only, synthesizes D1/D10
rows only in the proof bronze tables, and checks D0 isolation, D1 selection, D5
fallback, numeric ordering, invalid inputs, empty results and schema-mismatch
rejection. Both proof schemas are dropped afterwards. No bundle deploy/job run
is needed to exercise the creation SQL and parameterized calls.
