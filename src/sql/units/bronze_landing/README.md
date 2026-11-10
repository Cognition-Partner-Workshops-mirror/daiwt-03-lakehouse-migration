# Bronze golden-input landing

`bronze_landing` reads the ten golden input CSVs at
`${golden_path}/inputs/<drop>/core.<table>.csv` into
`${catalog}.${bronze_schema}.<table>`. The golden volume is **read-only**.
The unit owns only these bronze tables and has no parity outputs or dependencies.
Its warehouse SQL-file tasks load the snapshot, then self-check counts and ordered
columns against `${golden_path}/manifest.json`, raising an error on any mismatch.
The job accepts `drop` (default `D0`) and bundle catalog/layer/golden-path parameters;
target permissions are inherited from the bundle.

## Types and columns

Columns are in source DDL/manifest order. All source `VARCHAR`, `CHAR(4)` and
`SUPER` columns become `STRING`, preserving padding, case and raw JSON text.
`NUMERIC(12,2)` becomes `DECIMAL(12,2)`; source `TIMESTAMP` becomes
`TIMESTAMP_NTZ`. `BIGINT`, `INT`, `DATE`, `BOOLEAN` and source key `NOT NULL`
constraints are preserved. Every table ends with `_drop STRING` and
`_loaded_at TIMESTAMP` (the load's current timestamp).

| Table | Source columns and target types |
| --- | --- |
| `customers` | customer_id BIGINT, email STRING, first_name STRING, last_name STRING, phone STRING, region STRING, preferred_store_id INT, signup_date DATE, is_business BOOLEAN |
| `stores` | store_id INT, region STRING, store_name STRING, city STRING, state STRING |
| `products` | product_id INT, sku STRING, product_name STRING, category STRING, subcategory STRING, unit_price DECIMAL(12,2), cost DECIMAL(12,2), active BOOLEAN |
| `orders` | order_id BIGINT, customer_id BIGINT, store_id INT, order_ts TIMESTAMP_NTZ, sales_channel STRING, status STRING |
| `order_items` | order_item_id BIGINT, order_id BIGINT, product_id INT, quantity INT, unit_price DECIMAL(12,2), discount DECIMAL(12,2) |
| `payments` | payment_id BIGINT, order_id BIGINT, method STRING, amount DECIMAL(12,2), paid_ts TIMESTAMP_NTZ |
| `returns` | return_id BIGINT, order_item_id BIGINT, quantity INT, reason STRING, returned_ts TIMESTAMP_NTZ |
| `shipments` | shipment_id BIGINT, order_id BIGINT, carrier STRING, ship_ts TIMESTAMP_NTZ, delivered_ts TIMESTAMP_NTZ |
| `web_events` | event_id BIGINT, customer_id BIGINT, event_ts TIMESTAMP_NTZ, event_type STRING, page_url STRING |
| `campaign_touches` | touch_id BIGINT, customer_id BIGINT, payload STRING |

The reader uses explicit STRING input columns, RFC4180 quote/escape settings,
multiline records, no whitespace stripping, strict header handling and fail-fast
malformed/rescued-row checks. Each field is normalized with
`NULLIF(COALESCE(field, ''), r'\N')` before a strict cast to its target type.
This is deliberate: the CSV parser represents an **unquoted empty field** as
SQL NULL even when `nullValue` is configured as `\N`. Reading with an empty
parser null marker retains the literal `\N` text; normalization then distinguishes
it from both quoted and unquoted empty strings. Invalid typed values fail rather
than being silently coerced to NULL. No trimming, casing or JSON parsing is applied.

Bound parameter expressions for `read_files` paths were verified directly on
warehouse `6dc4b80538621b7b`; dynamic SQL is not needed. The D0 load and self-check
were executed in `devin_dev.d03_bronze_scratch_1794327707`, including a second load
that preserved an earlier-drop row without duplicating D0. The scratch schema
was dropped afterwards. The source D0 inputs have no empty fields; a separate
warehouse CSV-parser probe verified NULL versus quoted/unquoted empty strings
and padding with the same normalization.

## Snapshot reads

Each drop is a full snapshot. Loading creates missing tables, deletes **only**
rows for `:drop`, then inserts that drop and its lineage. Earlier drops are kept.
The delete/insert sequence is not a multi-statement transaction: after failure,
rerun the job to repair that drop. Do not run concurrent loads into the same tables.
Downstream builders should depend on `bronze_landing` and filter every input by
the explicit job drop to avoid mixing snapshots:

```sql
SELECT * EXCEPT (_drop, _loaded_at)
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers')
WHERE _drop = :drop;
```

For the **most recently loaded** snapshot (not lexicographically largest label):

```sql
WITH latest AS (
  SELECT _drop
  FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers')
  GROUP BY _drop
  ORDER BY max(_loaded_at) DESC, _drop DESC
  LIMIT 1
)
SELECT c.*
FROM IDENTIFIER(:catalog || '.' || :bronze_schema || '.customers') AS c
JOIN latest USING (_drop);
```

An empty snapshot has no lineage rows, so select empty/latest drops using the
manifest's declared drop and an explicit `:drop`, not row timestamps. A rerun of
an earlier drop makes it the most recently loaded snapshot.
