# Insimul default-UI (Godot) — registry, theme tokens, loading screen

This is the Godot leg of the shared default-runtime UI (plan §4.5). It is the
third mirror of the same contract the Babylon reference and the Unity/Unreal
plugins implement, so the **behavior** and the **design tokens** are pinned by an
engine-neutral corpus under `packages/core/conformance/ui/` — every engine runs
the same cases.

## Panel registry — `InsimulUiRegistry`

`addons/insimul/ui/insimul_ui_registry.gd` maps a stable panel **key** to a Godot
scene, with a creator **override** layer and **missing-panel diagnostics**.

- **Default map** — `InsimulUiRegistry.DEFAULT_PANELS` ships the twelve default
  panels (`loading_screen`, `notifications`, `hud`, `main_menu`, `game_menu`,
  `quest_journal`, `quest_tracker`, `quest_offer`, `inventory`, `container`,
  `merchant`, `dialogue`). The key list is pinned by
  `conformance/ui/registry-cases.json → panel_keys`.
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

`addons/insimul/tests/ui_registry_test.gd` runs the shared corpus against the
view-models (registry precedence + diagnostics, loading-phase progress/label/
complete, notification lifecycle, token→Theme smoke). Run it via
`addons/insimul/tests/run_ui_registry_headless.sh` (wired into
`npm run engines:check`); it skips cleanly when no `godot` binary is present, and
the GDScript structural lint covers the `.gd` files regardless.
