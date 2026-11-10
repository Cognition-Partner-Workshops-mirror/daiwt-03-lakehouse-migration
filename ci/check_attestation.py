"""Accept reusable D0 evidence only when its content fingerprint is current."""
import argparse
import json
import re
import shlex
import subprocess
from pathlib import Path

from classify_changes import classify_diff, fingerprint
from record_attestation import COLUMNS, TABLE, Warehouse, table_name


def evaluate(rows, head_sha, required_units, fingerprint_fn=fingerprint):
    reasons = []
    for row in rows:
        try:
            units = json.loads(row['units'])
            drops = json.loads(row['drops'])
            if not isinstance(units, list) or not all(isinstance(u, str) for u in units):
                raise ValueError('invalid units')
            if row['status'] != 'PASS' or drops['D0']['status'] != 'PASS':
                raise ValueError('failed D0 or attestation status')
            if not set(required_units) <= set(units):
                raise ValueError('insufficient recorded units')
            if row['fingerprint'] != fingerprint_fn(head_sha, units):
                raise ValueError('stale fingerprint')
            if not row['attestation_md']:
                raise ValueError('missing markdown')
            return row, 'PASS'
        except (ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
            reasons.append(str(exc))
    return None, '; '.join(reasons) or 'no matching PASS attestation'


def check(head, base, suffix, query, fingerprint_fn=fingerprint, classify_fn=classify_diff):
    required = classify_fn(base, head)
    if not required['required']:
        return True, 'No attestation required (docs/tests only)'
    fp = fingerprint_fn(head, required['units'])
    rows = query(fp, suffix)
    row, reason = evaluate(rows, head, required['units'], fingerprint_fn)
    if row:
        return True, row['attestation_md']
    units = ','.join(required['units'])
    command = f"bash ci/dev_verify.sh {suffix} '{units}'"
    return False, (f"**FAIL** — {reason}\n\nRequired units: {json.dumps(required['units'])}"
                   f"\n\nRun:\n```bash\n{command}\n```\n")


def main():
    parser = argparse.ArgumentParser()
    for name in ('head-sha', 'base-sha', 'suffix'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--output', default='attestation.md')
    args = parser.parse_args()
    try:
        if not re.fullmatch(r'pr_[0-9]+', args.suffix):
            raise ValueError('invalid PR suffix')

        def query(fp, suffix):
            from databricks.sdk import WorkspaceClient
            warehouse = Warehouse(WorkspaceClient(), '6dc4b80538621b7b')
            data = warehouse.sql(
                f"SELECT {', '.join(COLUMNS)} FROM {table_name(TABLE)} "
                "WHERE status = 'PASS' AND (fingerprint = :fp OR suffix = :suffix) "
                "ORDER BY recorded_at DESC", {'fp': fp, 'suffix': suffix})
            return [dict(zip(COLUMNS, row)) for row in data]

        ok, body = check(args.head_sha, args.base_sha, args.suffix, query)
    except Exception as exc:
        ok = False
        try:
            units = classify_diff(args.base_sha, args.head_sha)['units']
        except Exception:
            units = ['*']
        body = (f"**FAIL** — attestation query or selection failed: {exc}\n\n"
                f"Required units: {json.dumps(units)}\n\n"
                f"bash ci/dev_verify.sh {shlex.quote(args.suffix)} '{','.join(units)}'\n")
    Path(args.output).write_text(body + '\n')
    print(body)
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
