# Binding Editor dock (US-GB3)

The editor-time dock for managing the Asset Binding Layer (US-GB1): a taxonomy
tree with bound/unbound status, a scene picker, bind-descendants, name/tag
suggestions over the project, and pack import/export. Registered into the editor
by `insimul_plugin.gd` (`add_control_to_dock(DOCK_SLOT_RIGHT_UL, ...)`).

## Logic layer vs UI (the story's split)

- `insimul_binding_dock_model.gd` — `InsimulBindingDockModel`, a **UI-free**
  `RefCounted`. Owns the testable logic: `build_taxonomy_tree(archetypes)`,
  `bound_keys` / `unbound_keys`, `suggest_bindings(archetype, assets)` (ranks
  project assets by how many of the archetype's dot segments appear in the asset
  name / path / tags), `bind` / `bind_descendants` / `unbind`, and
  `export_pack_json` / `import_pack_json` (the `insimul-binding-pack` interchange
  shared with Unity/Unreal). Exercised headless by
  `binding_dock_test.gd` (`run_binding_dock_headless.sh`, SKIPs without a `godot`
  binary; the structural lint covers it on a bare box).
- `insimul_binding_dock.gd` — `InsimulBindingDock`, the `@tool Control`. A thin
  view: a two-column `Tree` (archetype / binding, green = bound, red = unbound),
  a toolbar (Bind Scene…, Bind Descendants…, Unbind, Import Pack…, Export Pack…),
  and `EditorFileDialog` pickers. Needs a running editor to exercise, so it is
  only structurally checked (the lint) here and verified by the human end-to-end
  pass (`VERIFICATION.md`).

## Bind-descendants

Binding a **non-leaf** taxonomy key (e.g. `building`) covers every descendant
archetype (`building.residential`, `building.commercial`, …) that has no more
specific entry — the descendant matching lives in the resolver
(`InsimulBindingResolver` / `binding_resolver.cpp`). `bind_descendants(parent,
scene)` is a documented alias for `bind(parent, scene)` that makes the intent
explicit in the UI.

## Suggestions

`suggest_bindings("building.residential", assets)` scores each asset by the count
of the archetype's dot segments (`building`, `residential`) found
case-insensitively in the asset name/path/tags, returns only score > 0, sorted by
score descending then path ascending (deterministic). The dock offers the top hit
as the default scene-picker target.
