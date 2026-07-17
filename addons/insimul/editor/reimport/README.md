# Re-import diff policy (US-GB3)

When a world's IR is re-exported and its scene regenerated, the editor must
reconcile the freshly computed placement manifest (US-GB2) against the scene tree
already on disk **without clobbering a human's hand edits**. This is the shared
re-import policy — identical across the Unity and Unreal legs.

## The policy (five actions, keyed by InsimulEntityId)

| action | condition | effect |
| ------ | --------- | ------ |
| **added** | in NEW manifest, absent from OLD scene | materialize a new generated node |
| **updated** | in BOTH, OLD is `generated:true`, transform/asset changed | re-apply the generated state |
| **unchanged** | in BOTH, OLD is `generated:true`, byte-identical | no-op |
| **skipped** | OLD is `generated:false` (a hand edit) | preserve verbatim — present *or* absent from NEW |
| **deprecated** | OLD is `generated:true` but absent from NEW | move under a **Deprecated** group node, never delete |

Two invariants make it safe to re-run at any time:

- **generated-only updates** — only nodes flagged `insimul_generated == true` are
  ever touched. A node the user re-flagged `insimul_generated = false` (a manual
  override / hand edit) is left exactly as it is.
- **never auto-delete** — a generated node the new manifest drops is *moved*, not
  removed, so the human reviews it in the Deprecated group.

The diff is a **dry-run report** first (pure, side-effect-free); the editor renders
it as a preview, then `apply_reimport()` mutates the tree.

## Host-vs-editor split (the load-bearing pattern)

The **classification policy** is the cross-engine contract, so it lives in a
dependency-free C++ core host-tested on a bare box; the **tree reconciliation** is
the GDScript twin gated on a real Godot binary:

- `gdextension/src/reimport_diff.{h,cpp}` — the std-only diff core.
  `compute_reimport_diff(old_nodes, new_nodes)` → `serialize_diff_report(...)`
  emits the canonical dry-run report (key-sorted, minified). Host gate:
  `gdextension/test/run_reimport_tests.sh` (golden-match + policy-coverage +
  determinism + no-op). This is the authority.
- `insimul_reimport.gd` — the `@tool` twin. `compute_diff(old, new)` mirrors the
  classification exactly; `apply_reimport(existing_root, fresh_root)` reconciles
  the live scene tree (update generated in place, reparent added, move dropped
  generated under the `Deprecated` group, leave hand edits untouched). Headless
  gate: `run_reimport_headless.sh` (SKIPs with exit 0 when no `godot` binary is
  present — the host gate holds the contract there).

A single set of shared fixtures drives BOTH so they can never diverge.

## Fixtures

- `fixtures/old-manifest.json` — a "previous scene" manifest exercising every
  action: a generated node identical to NEW (unchanged), a generated node moved
  (updated), a hand edit present in NEW (skipped), a generated node dropped from
  NEW (deprecated), and a hand edit dropped from NEW (skipped).
- `fixtures/new-manifest.json` — the freshly generated manifest (adds one
  new-only node).
- `fixtures/golden-diff-report.json` — the expected canonical dry-run report.
  **Regenerate** with `bash gdextension/test/run_reimport_tests.sh dump` (never by
  hand) after any change to the policy or the manifests, then commit.

## Report shape

```json
{
  "reportVersion": 1,
  "added": ["<entityId>", ...],
  "updated": [...],
  "unchanged": [...],
  "skipped": [...],
  "deprecated": [...],
  "counts": { "added": <n>, "updated": <n>, "unchanged": <n>, "skipped": <n>, "deprecated": <n> }
}
```

Every id list is emitted in ascending order and the serialization is canonical
(key-sorted, minified) so two runs — or two engines — produce byte-identical
reports.
