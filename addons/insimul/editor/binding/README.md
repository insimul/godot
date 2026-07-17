# Asset Binding Layer — Godot (US-GB1)

Editor-time mapping from **archetype keys** (dot-path taxonomy labels such as
`building.residential.house`) to **PackedScene / Mesh** assets, plus transform
fixups and named sockets. This is the Godot mirror of the Unity/Unreal binding
layers; the pack format and resolution semantics are the **cross-engine
contract**.

## Files

- `insimul_binding_table.gd` — `InsimulBindingTable`, a `.tres`-friendly
  `Resource` holding one resolution tier (`source_name`, `priority`, sorted
  `entries`). Import/export portable pack JSON; owns the archetype matcher.
- `insimul_binding_resolver.gd` — `InsimulBindingResolver`, resolves a query key
  against a prioritized fallback chain of tiers (project → packs → placeholder).
- `binding_resolver_test.gd` + `run_binding_resolver_headless.sh` — the editor
  gate (runs against a real Godot binary; **skips** on the bare Ralph box).
- `fixtures/resolver-matrix.json` — the **shared resolver test matrix** driving
  both the GDScript gate and the host C++ gate.
- `fixtures/unity-fixture-pack.json` — a foreign (Unity-authored) pack proving
  the cross-engine round-trip.

The authoritative gate on a box with no Godot binary is the host C++ twin
`packages/godot/gdextension/src/binding_resolver.{h,cpp}` +
`gdextension/test/run_binding_tests.sh` (wired into `npm run engines:check`).
The two implementations MUST stay byte-identical against the shared matrix.

## Portable pack format (`insimul-binding-pack`)

```json
{
  "format": "insimul-binding-pack",
  "version": 1,
  "name": "unity-core",
  "priority": 40,
  "entries": [
    {
      "key": "building.residential.house",
      "scene": "res://.../house.tscn",
      "mesh": "",
      "transform": { "offset": [x,y,z], "rotation": [x,y,z], "scale": [x,y,z] },
      "sockets": { "door": [x,y,z] }
    }
  ]
}
```

Asset refs are opaque strings — Godot uses `res://` paths, Unity uses GUID/asset
paths — but the **schema is identical** across engines, so a pack authored by
one engine imports into another unchanged. Export is **sorted** (entries
ascending by key), so a saved `.tres` / pack JSON is byte-deterministic.

## Resolution semantics

Given a query key, `match_archetype` scores each entry key:

| kind         | matches                                        | rank |
|--------------|------------------------------------------------|------|
| `exact`      | `entry == query`                               | 3    |
| `descendant` | `query` starts with `entry + "."`              | 2    |
| `wildcard`   | `entry` is `"*"` or `"prefix.*"`               | 1    |

Specificity ranks by **matched segment count first**, then match kind. The
resolution chain is a **fallback**: tiers are consulted highest-priority first
(`project` → `packs` → `placeholder`); the **first tier with any match wins**,
and within it the **most specific** entry is chosen. Ties keep the
earlier-declared entry.
