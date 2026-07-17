# Generated GDScript DTOs (`Insimul*`)

**Do not edit these files by hand.** They are emitted by the runtime codegen
pipeline from the canonical `@insimul/core` JSON Schemas.

- **Regenerate:** `npm run codegen` (from the `insimul-runtime` root)
- **Source of truth:** `packages/core/schemas/{save-file,save-envelope,world-ir}.schema.json`
- **Emitter:** `tools/codegen/emit-gdscript.mjs` (hand-rolled Godot 4 GDScript
  emitter — quicktype has no GDScript target)
- **Drift guard:** `tools/codegen/__tests__/codegen-drift.test.ts` regenerates into
  a temp dir and byte-diffs against these committed files; CI fails on drift.
- **Syntax check:** `npm run codegen:verify-gdscript`. It prefers a real
  `godot --headless --check-only` when a `godot` binary is on `PATH`; otherwise it
  runs the structural self-test in `tools/codegen/gdscript-verify.mjs` (balanced
  brackets, tab indentation, `class_name`/`from_dict`/`to_dict`, and every schema
  field key present). No Godot binary ships in this harness, so CI uses the
  fallback.

## What's here

One script per top-level schema, each a Godot 4 `class_name` type extending
`RefCounted`:

- `InsimulSaveFile.gd` — `class_name InsimulSaveFile`
- `InsimulSaveFileEnvelope.gd` — `class_name InsimulSaveFileEnvelope`
- `InsimulWorldIR.gd` — `class_name InsimulWorldIR`

Each declares typed member vars (snake_case, mapped back to the camelCase JSON
keys), a `static func from_dict(d: Dictionary)` that validates and populates the
type (`push_warning` on a missing required field, an unknown field, or an invalid
enum value), and a `func to_dict() -> Dictionary`. Nested objects with declared
properties become inner classes (e.g. `SaveFile`'s `WorldSnapshot` / `World` /
`CurrentState`); freeform objects (`additionalProperties`) are typed `Dictionary`
and opaque lists `Array`. A `$ref` across the top-level schemas (the envelope's
`saveFile`) is emitted as a reference to the sibling global class
(`InsimulSaveFile`), resolved through Godot's `class_name` registry.

## The hand-written boundary convention

**These generated types are the wire/DTO layer** — a faithful 1:1 image of the
core save/world JSON contract, safe to regenerate on any schema change. The
hand-written SDK types the rest of the addon uses stay in
`addons/insimul/insimul_types.gd` (`InsimulTypes` — the proto-derived conversation
event types) and the other `insimul_*.gd` scripts; those are **not** schema-derived
and must not be replaced by codegen. Adapt at the boundary: parse a save/world
payload into these generated DTOs, then read fields off them (or convert into
richer runtime objects). When a schema field is added, regenerate here and extend
the consuming code to carry the new field across.
