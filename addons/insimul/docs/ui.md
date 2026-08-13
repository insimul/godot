# Insimul default-UI (Godot) — registry, theme tokens, loading screen

This is the Godot leg of the shared default-runtime UI (plan §4.5). It is the
third mirror of the same contract the Babylon reference and the Unity/Unreal
plugins implement, so the **behavior** and the **design tokens** are pinned by an
engine-neutral corpus vendored at `conformance/ui/` — every engine runs the same
cases.

## Panel registry — `InsimulUiRegistry`

`addons/insimul/ui/insimul_ui_registry.gd` maps a stable panel **key** to a Godot
scene, with a creator **override** layer and **missing-panel diagnostics**.

- **Default map** — `addons/insimul/ui/panels.json`, read by
  `InsimulUiRegistry.shipped()`. Panel key → the scene under
  `addons/insimul/ui/scenes/` that serves it, plus the modules it needs. The key
  list is pinned by `conformance/ui/registry-cases.json → panel_keys`, in both
  directions, by `tools/verify-ui/check-ui.mjs`.

  The registry file itself spells **no panel key and no module id** — the same
  discipline `insimul_module_activation.gd` works by, for the same reason: "a
  creator swaps a panel with no engine code change" is only true while the engine
  code has nothing to change. The gate greps for both and fails on a hit.
- **Creator override** — a per-key override always wins over the shipped default.
  Two sources, applied in order (later wins): the project setting
  `insimul/ui/panel_overrides` (a `{ key: scene_path }` Dictionary, loaded by
  `load_project_overrides()`), then explicit `register(key, ref)` calls.
- **Diagnostics** — `scene_ref(key)` / `instantiate(key)` record a diagnostic
  (`{ kind, key, message }`) for an unknown key or an unloadable scene, surfaced
  via `diagnostics()` / `has_diagnostics()`. A creator sees exactly which panel is
  blank and why.
- **Two resolution levels** — `scene_ref(key)` is pure data (no disk access, what
  the shared cases exercise); `instantiate(key)` loads + instantiates the
  `PackedScene` at runtime.

### The module gate (band 111)

Every panel resolves through the **module registry**: `panels.json` may declare
`requires: [<module id>]` against the activation table
(`conformance/modules/genre-activation.json`), and a panel whose modules the world
does not activate does not resolve **at all** — `scene_ref()` answers `""`,
`instantiate()` answers `null`, and a `module_inactive` diagnostic says which
module is missing. A game that offers a merchant button for a world with no trade
system is the failure this removes.

```gdscript
var ui := InsimulUiRegistry.shipped()
ui.bind_activation(InsimulModuleActivation.for_world(world_ir))
if ui.is_available("merchant"):
    add_child(ui.instantiate("merchant"))
```

Three things worth knowing:

- **Gating is off until an activation is bound.** A registry nobody told about the
  world shows everything — which is what an editor session, a unit test and the
  shared cases all want.
- **An UNDECLARED activation is not an empty one.** `bind_activation()` clears the
  gate when the activation declares no genre, matching
  `InsimulModuleActivation`'s own "nothing was declared, so the whole vocabulary
  is in play". Pass `set_active_modules([])` to mean the opposite.
- **`bind_activation()` is duck-typed** (`module_ids()` + `genre()`). Nothing under
  `addons/insimul/ui/` may name `InsimulCore`, and the gate enforces it: the
  default UI has to load in a project with no native build, or a missing
  GDExtension takes the menus down with it.

## Theme tokens — `InsimulUiTokens`

`addons/insimul/ui/insimul_ui_tokens.gd` mirrors
`conformance/ui/theme-tokens.json` (the single source of truth) as GDScript
constants, and `build_theme()` realizes them as a Godot `Theme` resource. Keep the
two in lockstep with the JSON — a divergence is a parity bug.

### Token → Theme mapping

| Token (theme-tokens.json)     | Value      | Godot `Theme` binding |
| ----------------------------- | ---------- | --------------------- |
| `colors.background`           | `#12141c`  | loading-screen `ColorRect` fill |
| `colors.surface`              | `#1b1e2a`  | `Panel`/`PanelContainer` stylebox bg; toast bg |
| `colors.surface_alt`          | `#242838`  | `Button:disabled`, `ProgressBar` background bg |
| `colors.overlay`              | `#0a0b10cc`| modal scrims (dialogue / menus) |
| `colors.border`               | `#333a52`  | stylebox border color |
| `colors.text_primary`         | `#eef1f8`  | `Label`/`RichTextLabel`/`Button` `font_color` |
| `colors.text_secondary`       | `#9aa3bd`  | `ProgressBar` `font_color`; loading tip |
| `colors.text_disabled`        | `#5a6076`  | `Button` `font_disabled_color` |
| `colors.accent`               | `#5b8cff`  | `Button:normal` bg; `ProgressBar` fill |
| `colors.accent_hover`         | `#7aa2ff`  | `Button:hover` bg |
| `colors.accent_pressed`       | `#3f6fe0`  | `Button:pressed` bg |
| `colors.success`              | `#4ecb8d`  | success toast border |
| `colors.warning`              | `#e6b34d`  | warning toast border |
| `colors.danger`               | `#e05a6a`  | danger toast border |
| `colors.quest`                | `#c9a24b`  | quest markers/highlights |
| `spacing.{xs,sm,md,lg,xl}`    | 4/8/12/16/24 | stylebox content margins, container separation |
| `radius.{sm,md,lg}`           | 4/8/12     | stylebox corner radii |
| `font_size.{caption,body,title,display}` | 12/16/22/32 | `font_size` overrides |

## Loading screen + notifications (the pattern-proof pair)

Both follow the same **model + thin Control** split so the logic is unit-testable
without a scene tree:

- **`InsimulLoadingScreenModel`** (`loading_screen_model.gd`) — driven by the boot
  loop (`world source → save slot → KB → systems init`). Advancing through the
  ordered weighted phases yields a **monotonic** progress fraction, a phase label,
  and a deterministic tip. Phases/weights/tips mirror
  `conformance/ui/loading-phases.json`; progress at a phase = cumulative weight
  through that phase ÷ total weight. `InsimulLoadingScreen` (Control) renders it
  and emits `finished` at the terminal phase.
- **`InsimulNotifications`** (`insimul_notifications.gd`) — a timing-driven toast
  queue: `push(text, kind, lifetime)`, `tick(delta)` ages entries out,
  `dismiss(id)` removes early. `kind` maps to a token color.
  `InsimulNotificationCenter` (Control) renders it.

## Tests

Two gates, because one of them cannot run everywhere:

- **`addons/insimul/tests/ui_registry_test.gd`** (`npm run test:ui`, via
  `run_ui_registry_headless.sh`) runs the shared corpus against the view-models on
  a real Godot binary: registry precedence + diagnostics, loading-phase
  progress/label/complete, notification lifecycle, the full token mirror, the
  shipped manifest (every key, every scene, `instantiate()` reaching a real
  `Control`), the creator override through the project setting, and the module
  gate across every genre bundle in the activation table. It stages **only**
  `addons/insimul/ui/` plus the test, imports the project first — without that
  pass Godot registers no global `class_name` and every script fails to parse
  while `godot -s` still exits 0 — and then fails on any script error in the log.
  With no `godot` binary it SKIPS.
- **`tools/verify-ui/check-ui.mjs`** (`npm run check`) needs nothing but Node, so
  the parity claims still have a gate on a box with no Godot: the manifest and the
  corpus document the same panels (both ways), every scene and every scene
  dependency is a real file, every gated module is in the activation table and is
  activated by some bundle, the registry names neither a panel nor a module, the
  token set matches the corpus (both ways), and nothing in the UI calls into
  `InsimulCore`. Every check has a negative control under `--self-test`.
