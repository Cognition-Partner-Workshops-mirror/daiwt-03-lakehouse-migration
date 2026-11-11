import asyncio
import json
import pathlib

import yaml

CONFIG = json.loads(pathlib.Path.home().joinpath("migration_run.json").read_text())
REPO = CONFIG["repo"]
UNITS = yaml.safe_load(pathlib.Path(CONFIG["units_yml"]).read_text())["units"]

SCHEMA = {
    "type": "object",
    "properties": {
        "unit": {"type": "string"},
        "pr_url": {"type": "string"},
        "merged": {"type": "boolean"},
        "offline_parity": {"type": "string"},
        "findings": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["unit", "pr_url", "merged", "offline_parity"],
}


def brief(unit):
    return (
        f"Use the `dbx-migrate-unit` skill to migrate unit `{unit['name']}` in {REPO}.\n"
        f"Unit plan (from docs/units.yml):\n{json.dumps(unit, sort_keys=True, indent=2)}\n"
        "Touch only src/units/<unit>/. No Databricks deploys or job runs. "
        "Do not wait for upstream units or merges: fetch-goldens --units <unit> and "
        "check --units <unit> use manifest table mappings for upstream output goldens, "
        "even when no upstream unit directory exists. "
        "Merge your PR as soon as the `pr` workflow is green. Report the structured output."
    )


async def build(unit):
    try:
        return await agent(brief(unit), phase="migrate", schema=SCHEMA, label=unit["name"],
                           repos=[REPO], soft_time_limit_minutes=20)
    except WorkflowAgentError as error:
        log(f"{unit['name']}: builder failed: {error}")
        return {"unit": unit["name"], "pr_url": "", "merged": False, "offline_parity": "ERROR"}


async def main():
    await register_workflow({
        "name": "dbx-migrate-estate",
        "description": f"One builder per unit for {REPO}, all in parallel",
        "phases": [{"title": "migrate", "detail": "translate + offline parity + merge, one PR per unit",
                    "labels": [u["name"] for u in UNITS]}],
        "soft_time_limit_minutes": 20,
    })
    results = await parallel([lambda u=u: build(u) for u in UNITS])
    for r in results:
        log(f"{r['unit']}: merged={r['merged']} parity={r['offline_parity']} {r['pr_url']}")
    missing = [r["unit"] for r in results if not r["merged"]]
    log("ALL MERGED" if not missing else f"NOT MERGED: {', '.join(missing)}")


asyncio.run(main())
