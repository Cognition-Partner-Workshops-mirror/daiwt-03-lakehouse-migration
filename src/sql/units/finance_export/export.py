# Databricks notebook source
# Monthly finance export: one CSV with header of finance_monthly ordered by month.
import csv
import io
import os

dbutils.widgets.text("catalog", "")
dbutils.widgets.text("gold_schema", "")
dbutils.widgets.text("export_dir", "")
catalog = dbutils.widgets.get("catalog")
gold_schema = dbutils.widgets.get("gold_schema")
export_dir = dbutils.widgets.get("export_dir").rstrip("/")
assert catalog and gold_schema and export_dir.startswith("/Volumes/"), "catalog, gold_schema and a /Volumes export_dir are required"

df = spark.sql(
    "SELECT * FROM IDENTIFIER(:t) ORDER BY month",
    args={"t": f"`{catalog}`.`{gold_schema}`.`finance_monthly`"},
)
rows = df.collect()
buf = io.StringIO()
writer = csv.writer(buf, lineterminator="\n")
writer.writerow(df.columns)
for row in rows:
    writer.writerow(["" if v is None else str(v) for v in row])

target = f"{export_dir}/monthly/finance_monthly.csv"
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, "w", encoding="utf-8") as fh:
    fh.write(buf.getvalue())

with open(target, encoding="utf-8") as fh:
    written = fh.read()
assert written == buf.getvalue() and written.count("\n") == len(rows) + 1, f"export check failed for {target}"
print(f"wrote {len(rows)} rows to {target}")
