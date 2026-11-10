# daiwt-03 Lakehouse migration

Clean pre-migration baseline for the Redshift estate
[`daiwt-03-redshift`](https://github.com/Cognition-Partner-Workshops-mirror/daiwt-03-redshift),
using the vendored `migration-ci` framework. There are no migrated units yet.
`estate.yml` is the only estate configuration; `golden/manifest.json` is retained
as the captured D0 inventory. Golden CSVs stay in Unity Catalog, not in git.

| Setting | Value |
| --- | --- |
| Dev / prod catalogs | `daiwt_03_mig_dev` / `daiwt_03_mig_prod` |
| SQL warehouse | `6dc4b80538621b7b` |
| Golden volume | `/Volumes/daiwt_03_mig_prod/landing/golden` |
| Drops | `D0` |

## Demo flow

1. `dbx-understand-legacy-estate` regenerates `docs/units.yml`. Historical source
   findings in `docs/discovery/` are plain reference documentation, not a registry.
2. Builders add only `src/units/<unit>/unit.yml` and that unit's ordered SQL files.
   Dependencies are inferred from SQL references; no shared contract or attestation.
3. PRs run fast offline checks and strict bundle validation, never deployment.
4. Manually dispatch `integrate.yml` with `drops=all` for one dev integration.
   `promote.yml` is manual-only and uses the prod environment.
5. Manually dispatch `reset.yml` with `target=dev|prod` to destroy the selected
   bundle and remove its bronze/silver/gold/verification schemas. Landing goldens
   are preserved. A zero-unit integration lands bronze inputs but proves no unit parity.

GitHub Actions uses Devin-CI OIDC, repository variables `DATABRICKS_HOST` and
`DATABRICKS_CLIENT_ID`, and environments `dev` / `prod`; no runtime secrets.
The vendored Devin orchestration entrypoint is
`.migration/framework/workflows/migrate_estate.py` and reads `~/migration_run.json`.

## Migration CI

Install `python -m pip install -r requirements-dev.txt`. Add a directory under
`src/units/<name>/` with `unit.yml` and ordered SQL files; no shared registry.
Run `migration-ci fetch-goldens` then `migration-ci check` (or
`migration-ci check --goldens /path/to/local/goldens`). `pytest --goldens PATH`
runs the same offline gate. Plain pytest validates structure without remote data.
PRs run offline checks only. Manually dispatch integrate for dev integration,
then promote for production. Reset destroys only the selected bundle and its
bronze/silver/gold/verification schemas, never the landing golden volume.
Framework fixes propagate by running `migration-ci sync .` from a new framework
version and opening a PR for the changed vendored files.
