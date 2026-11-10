# Wave 0 discovery

These are historical, plain-documentation findings from the completed migration.
References to old contracts, registries and CI describe that earlier implementation;
the root README describes the current framework. The demo regenerates its plan at
`docs/units.yml` with `dbx-understand-legacy-estate`.

Technical handover for the D0 migration, anchored to `2025-12-31`.
Source paths in these documents refer to `daiwt-03-redshift` unless explicitly marked as migration-repo paths.

- [Inventory and dependency graph](inventory.md): source objects, waves, and silver reads per gold unit.
- [Target model](target_model.md): grains, keys, types, schemas, and publication semantics.
- [Business rules](business_rules.md): analyst semantic catalogue and golden column impact.
- [Builder notes](builder_notes.md): wave-by-wave implementation checklist with source line pointers.
- [Orchestration mapping](orchestration_mapping.md): schedule, task graph, exports, and governance.
- [Shared macros](shared_macros.md): foundation DDL, SQL UDF placement, and canonical Redshift expression templates (M1–M22).

Analyst evidence labels and recomputation results are retained as supplied. No source rebuild, golden capture, deployment, or data mutation is part of this handover.
