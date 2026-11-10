# Redshift golden capture

`capture_redshift.py` reproduces the capture by resetting and running the legacy
repository at the recorded commit, **not by reloading captured input CSVs**.
This is a destructive operator action on `daiwt_03_retail`, workgroup
`daiwt-03-retail`. Obtain the parent's explicit coordination go-ahead first.
It uses only the Redshift Data API, with UTC sessions and no networking changes.
Never run it during a migration or reconciliation session.

Install `requirements-dev.txt` plus `boto3` and `redshift_connector` (the latter is
imported by the unmodified legacy runner, not used for connections). AWS credentials
must be provided by the environment; the secret is referenced by ARN, not stored.

```bash
python golden/capture_redshift.py \
  --capture-dir "$HOME/golden-capture/daiwt_03/<capture_id>" \
  --legacy-repo https://github.com/Cognition-Partner-Workshops-mirror/daiwt-03-redshift.git \
  --commit 1bee48ad399b81b9764d5ac9a0e3f30fad0fd22a \
  --captured-at 2026-11-10T14:24:33Z
```

The capture directory is outside the repository and OS temporary directories:

- `legacy/`: scratch clone, untouched source files; its own runner rewrites goldens.
- `run/`: start/end, log with `EXIT 0`, UTC session evidence, profile and verification.
- `inputs/D0/core.<table>.csv`: deterministic live exports of all ten inputs.
- `outputs/D0/<unit>/<name>.csv`: every legacy table/report golden, byte-for-byte.
- `manifest.json`: checksums, row counts, source profile, formatting, skipped branches
  and the parity harness `tables` contract (reports excluded from that array).

`--skip-legacy-run` reuses a finished run in that same directory. It requires the
recorded commit, `run/legacy_start.txt`, `run/legacy_end.txt`, `run/legacy_run.log`
containing `EXIT 0` (or a timestamped `done` after `== capture`, with a provenance
note about the original launcher's post-run session-log failure), and
`run/sessions.json` recording UTC. It still profiles,
exports and verifies live data, so the estate must remain unchanged throughout.
Existing manifests are never overwritten. Duplicate legacy keys or non-total
legacy ordering fail capture rather than silently changing frozen outputs.

Only D0 exists: the legacy seed is anchored at 2025-12-31 and the ETL is a full
reload. Verification rechecks every checksum, key and table count, re-exports all
inputs and self-exports one multi-row output twice. This checks export determinism,
not a second ETL run. Committed-golden mismatches are recorded, not repaired.

Commit only the runner, tests, manifest and provenance/inventory documentation.
CSV data belongs only in the volume. After review, an operator uploads inputs,
outputs and then manifest last to the capture's staging path as Devin-Admin and
downloads the entire staging directory to verify every checksum. Child 3 alone
promotes staging to `/Volumes/daiwt_03_mig_prod/landing/golden/`. Keep the local
capture directory until promotion is finished. Never touch daiwt_02 resources.

## Frozen D0 artifacts

Capture `20261110T142433Z` is recorded in `manifest.json`, with operational evidence
in `PROVENANCE.json` and skipped paths/scheduler drift in `skipped_branches.json`.
The manifest is a byte-for-byte copy of the verified capture-directory manifest.
The staging path is
`/Volumes/daiwt_03_mig_prod/landing/golden/_staging/20261110T142433Z/`.

Follow the root README's current builder flow for the goldens PR: at a clean,
pushed HEAD, use the default Devin profile to run `bash ci/dev_verify.sh pr_<n>`
(or pass an explicit unit selection). PR CI runs offline tests, strict validation
and the pushed-head attestation check; it does not deploy. After recording passing
builder evidence, rerun failed PR checks. No golden data or landing volume is a
cleanup target.
