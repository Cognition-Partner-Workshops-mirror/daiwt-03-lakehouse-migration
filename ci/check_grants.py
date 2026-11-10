"""Read-only checks of deployed job ACLs and effective Unity Catalog privileges."""
import argparse
import json
import os
import subprocess
from pathlib import Path


SCHEMA_REQUIRED = {'USE_SCHEMA', 'CREATE_TABLE', 'CREATE_FUNCTION', 'CREATE_MATERIALIZED_VIEW',
                   'CREATE_VOLUME', 'SELECT', 'MODIFY', 'EXECUTE', 'READ_VOLUME', 'WRITE_VOLUME'}
VIEW_LEVELS = {'CAN_VIEW', 'CAN_MANAGE_RUN', 'CAN_MANAGE', 'IS_OWNER'}
MANAGE_LEVELS = {'CAN_MANAGE', 'IS_OWNER'}


def evaluate_job(permissions, principal, groups=()):
    users_levels, manager_levels = set(), set()
    for entry in permissions.get('access_control_list', []):
        levels = {permission['permission_level'] for permission in entry.get('all_permissions', [])}
        if entry.get('group_name') == 'users':
            users_levels.update(levels)
        if (entry.get('user_name') == principal or entry.get('service_principal_name') == principal
                or entry.get('group_name') in groups):
            manager_levels.update(levels)
    missing = []
    if not users_levels & VIEW_LEVELS:
        missing.append('users CAN_VIEW')
    if not manager_levels & MANAGE_LEVELS:
        missing.append('deployer CAN_MANAGE or IS_OWNER')
    return missing


def evaluate_uc(assignments, principal, groups, required, owner=None):
    identities = {principal, *groups}
    if owner in identities:
        return []
    privileges = {entry['privilege'] for assignment in assignments
                  if assignment.get('principal') in identities for entry in assignment.get('privileges', [])}
    if 'ALL_PRIVILEGES' in privileges or 'OWN' in privileges:
        return []
    return sorted(required - privileges)


def effective_assignments(client, kind, name):
    assignments, token = [], None
    while True:
        response = client.grants.get_effective(kind, name, max_results=0, page_token=token)
        assignments.extend(entry.as_dict() for entry in response.privilege_assignments or [])
        token = response.next_page_token
        if not token:
            return assignments


def check(client, summary):
    user = client.current_user.me()
    principal = user.user_name
    if not principal:
        raise ValueError('Cannot determine deploying principal')
    groups = {group.display for group in user.groups or [] if group.display}
    rows = []

    def record(resource, operation):
        try:
            missing = operation()
            rows.append((resource, 'FAIL' if missing else 'PASS', ', '.join(missing) if missing else 'Effective access verified'))
        except Exception as error:
            rows.append((resource, 'FAIL', str(error)))

    jobs = summary.get('resources', {}).get('jobs', {})
    if not jobs:
        rows.append(('bundle jobs', 'FAIL', 'No deployed job resources resolved'))
    for key, job in sorted(jobs.items()):
        def job_check(job=job):
            if not job.get('id'):
                return ['No deployed job ID resolved']
            return evaluate_job(client.jobs.get_permissions(str(job['id'])).as_dict(), principal, groups)
        record('job ' + key, job_check)

    variables = summary['variables']
    catalog = variables['catalog']['value']
    record('catalog ' + catalog, lambda: evaluate_uc(
        effective_assignments(client, 'catalog', catalog), principal, groups, {'USE_CATALOG'},
        client.catalogs.get(catalog).owner))
    for layer in ('bronze', 'silver', 'gold'):
        schema = variables[layer + '_schema']['value']
        if schema == 'landing':
            rows.append(('schema landing', 'FAIL', 'Layer schema unexpectedly resolves to landing'))
            continue
        name = catalog + '.' + schema
        record('schema ' + name, lambda name=name: evaluate_uc(
            effective_assignments(client, 'schema', name), principal, groups, SCHEMA_REQUIRED,
            client.schemas.get(name).owner))
    return rows


def markdown(rows):
    def cell(value):
        return str(value).replace('|', '\\|').replace('\n', ' ').replace('\r', ' ')
    return '| Resource | Status | Evidence / missing access |\n| --- | --- | --- |\n' + '\n'.join(
        '| ' + ' | '.join(cell(value) for value in row) + ' |' for row in rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', choices=('dev', 'prod'), required=True)
    parser.add_argument('--schema-suffix')
    args = parser.parse_args()
    command = ['databricks', 'bundle', 'summary', '-t', args.target, '-o', 'json', '--force-pull']
    if args.schema_suffix:
        command += ['--var', 'schema_suffix=' + args.schema_suffix]
    try:
        from databricks.sdk import WorkspaceClient
        summary = json.loads(subprocess.check_output(command, text=True))
        rows = check(WorkspaceClient(), summary)
    except Exception as error:
        rows = [('grant check', 'FAIL', str(error))]
    report = markdown(rows)
    print(report)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as output:
            output.write('\n## Deployment grant check\n\n' + report + '\n')
    return int(any(row[1] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
