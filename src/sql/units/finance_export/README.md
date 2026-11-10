# finance_export

Gold unit migrated from legacy Redshift `finance_export`.

- `etl.sql` -> `gold.finance_monthly`: monthly order count and line revenue with fiscal year (Feb start) and `f_fiscal_qtr` (from `sql_macros`).
- `report.sql` -> `gold.report_finance_export`: fiscal year/quarter summary.
- `export.py`: UNLOAD equivalent, one header CSV of `finance_monthly ORDER BY month` written to
  `<export_dir>/monthly/finance_monthly.csv`. Prod writes the Terraform-managed volume
  `<catalog>.exports.finance_export`; dev writes a bundle-managed volume `gold_<suffix>.finance_export`.
- Schedule: nightly 02:00 UTC (paused in dev).
