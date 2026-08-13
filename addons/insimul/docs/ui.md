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

### Two panel tiers, and the accounting between them

`panels.json` holds two kinds of entry, distinguished by one field:

| Tier | Marker | Rule |
| ---- | ------ | ---- |
| **pinned** | no `pending_corpus` | the key set must equal `conformance/ui/registry-cases.json → panel_keys` **exactly, both ways**. This is the cross-engine registry contract; a pinned key only Godot has is a divergence, and divergence is a bug. |
| **ahead-of-corpus** | `pending_corpus: "<what has to happen>"` | a panel this port ships before the shared corpus has a key for it. |

US-2 ships seven panels in the second tier — `skill_tree`, `minimap`, `fullmap`,
`quickbar`, `radial_menu`, `notice_board`, `documents`. The tier is a **waiting
room, not a parking lot**, and the gate enforces that in both directions: an entry
must say what it is waiting for, and a `pending_corpus` key that the corpus
*already* documents fails — so when core adds the key and the corpus is
re-vendored, the entry has to move rather than quietly stay.

An ahead-of-corpus panel that gates on **nothing** carries a `gate_note` naming
the module that would back it and why that module is the wrong answer. `documents`
and `notice_board` are both there: the nearest band-111 modules (`equipment`,
`routine`) are activated only by the rpg-ish bundles, and reading is exactly what
the educational / language-learning bundles — which activate no modules at all —
are for. An ungated panel is an answer, not an omission.

### Composite panels

A panel entry may declare `children: [<panel key>]`. `InsimulHud` is the one that
does: it mounts each child **through the registry**, so every child meets the
module gate on the way in — a world with no `map` module simply gets a HUD without
a minimap, and nothing anywhere had to ask whether the world has a map.

```gdscript
var hud := ui.instantiate(key) as InsimulHud
add_child(hud)
hud.mount(ui, key)      # children from the manifest, each gated
```

`InsimulGameMenu` is the other one: the in-game menu **shell**, which mounts the
tabbed pause menu and the notification centre and forwards open/close/toggle to
whichever child behaves like a menu (duck-typed on `toggle` + `open_menu`, so a
creator override keeps working).

`hud.gd` and `game_menu.gd` spell no panel key, including their own — the layout is
manifest data like everything else. `check-ui.mjs` greps a composite's script for
every key the same way it greps the registry, and check 9 widens that to **anything
that resolves panels**: a ui/ file calling `children()`, `tab_panel()` or
`tab_panels()` is a resolver and lives under the same rule, which is how the rule
reaches a file the gate was never told about.

## The panels

| Key | Script | View-model | Gate |
| --- | ------ | ---------- | ---- |
| `quest_journal` / `quest_tracker` / `quest_offer` | `quest_*_panel.gd` | `InsimulQuestJournalModel` | — |
| `inventory` | `inventory_panel.gd` | `InsimulTradeModel` | — |
| `container` / `merchant` | `container_panel.gd`, `merchant_panel.gd` | `InsimulTradeModel` | `equipment` |
| `skill_tree` | `skill_tree_panel.gd` | `InsimulSkillTreeModel` | `skill` |
| `minimap` / `fullmap` | `minimap_panel.gd`, `full_map_panel.gd` | `InsimulMapModel` | `map` |
| `quickbar` / `radial_menu` | `quickbar_panel.gd`, `radial_menu_panel.gd` | — | `agentAi` |
| `notice_board` / `documents` | `notice_board_panel.gd`, `documents_panel.gd` | — | none (see `gate_note`) |
| `dialogue` | `dialogue_panel.gd` | `InsimulChatModel` | — |
| `pause_menu` | `pause_menu.gd` | `InsimulPauseMenuModel` | — |
| `main_menu` / `save_load` | `main_menu.gd`, `save_load_panel.gd` | `InsimulSaveSlotModel` | — |
| `hud` / `game_menu` | `hud.gd`, `game_menu.gd` (composites) | — | — |

### Backed EXCLUSIVELY by `save.currentState`

`InsimulTradeModel` binds the **live** `currentState` Dictionary and mutates it in
place. It keeps no private item store, which is what makes a snapshot at any
moment the whole truth: reads hand back the save's own arrays (identity, not a
copy), and every op conserves the item census and the gold total. The shared
matrices in `conformance/ui/trade-cases.json` pin the arithmetic; the
state-location invariant itself is asserted in code, in `quest_trade_test.gd`.

The inventory, container and merchant panels **share one model** (`set_model`),
because they share the state it is bound to. Two models over one `currentState`
would still agree — there is no private store to diverge — but nothing would tell
the second one to look, so the model emits `state_changed` and the panels redraw
off it.

### Driven by the real quest system

`InsimulQuestJournalModel.bind_quest_system(system)` connects the live
`InsimulQuestSystem` signals — `quest_offered(quest_id, tick)`,
`quest_accepted(quest_id)`, `quest_completed(quest_id)` — and hydrates from the
system's own projections. A **radiant arrival** therefore lands in the journal
under the Available tab with no polling, and an accept or completion made anywhere
in the game shows up in the journal, the tracker HUD and the offer dialog at once
(they share the model, and it emits `changed`).

The binding is **duck-typed**, on signal names and `get_projection()`. It has to
be: the quest system reaches into the GDExtension and nothing under
`addons/insimul/ui/` may, or the default UI stops loading in a project with no
native build. `quest_trade_test.gd`'s `StubQuestSystem` carries the exact
signatures, so the stub *is* the interface under test.

### Streaming dialogue, and where the transcript lives

`InsimulDialoguePanel.bind_conversation_service(service)` takes anything with the
streaming SDK's three signals — `chunk_received(npc_id, text)`,
`response_complete(npc_id, full_text)`, `response_error(npc_id, error)` — and a
`send_message(character_id, text)`. That is the shape of the template's `AIService`
autoload, which `_ready()` picks up on its own when a game has one. It is
**duck-typed** for the same reason the quest binding is: nothing under `ui/` may
name a class that reaches into the GDExtension, and a creator swapping the provider
must keep working. `dialogue_menu_save_test.gd`'s `StubConversationService` carries
the exact signatures, so the stub *is* the interface under test.

The panel adds what a view-model cannot have: **TTS** and the **`insimul_lip_sync`**
hook, both fed from the settled NPC line on completion (never from an errored one),
and the **KB** sink that asserts each triggered action's Prolog fact exactly once.

History follows the same data-first rule as the quest and trade panels, applied to
the one piece of UI state that does not live in `currentState`: `bind_save(save)`
points the panel at the live save Dictionary, and `close_chat()` projects the
transcript into `save.conversations` as this character's `ConversationSummary` —
**updating** the existing row rather than appending a second one. In-flight and
errored bubbles never reach it.

### The ESC menu: two gates, different vocabularies

`InsimulPauseMenuModel` gates a TAB on the feature modules the active genre bundle
enabled (`knowledge-acquisition`, `proficiency`, `assessment`, …). That vocabulary
is **not** the band-111 module vocabulary the panel registry gates on (`skill`,
`map`, `equipment`, …), and conflating the two is the mistake to avoid here.

Both reach the same menu, because a tab's BODY is a shipped panel:

```json
"pauseMenuTabs":     { "journal": "quest_journal", "map": "fullmap", … },
"pauseMenuTabNotes": { "settings": "no shipped panel: engine settings are the GAME's …" },
"pauseMenuCloseTab": "resume"
```

`pause_menu.gd` reads that map through `InsimulUiRegistry.tab_panel()` and mounts
the answer with `instantiate()`, so the body meets the band-111 gate on the way in.
A tab whose panel this world gates off is **still offered** (its own gate said yes)
and renders the reason the registry recorded, rather than a blank pane. So does a
tab no shipped panel serves — and `pauseMenuTabNotes` accounts for every one of
those, in prose, with `check-ui.mjs` holding the two halves to the shipped tab set
in both directions. A tab in neither is a gate failure.

`pauseMenuCloseTab` is the one tab that dismisses the menu instead of showing a
body. It is data because a shell that spelled `resume` would stop answering the
moment a creator relabelled the tab set.

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

Three gates, because one of them cannot run everywhere:

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

  Two of its legs — every shipped panel instantiating and reaching `_ready()`, and
  the composite HUD mounting its gated children — run from `_process()` rather
  than `_initialize()`. The tree's `root` **is not in the tree** during
  `_initialize()`, so a panel added there never gets its `_ready()` and every
  "does this panel build itself?" check would pass vacuously.
- **`addons/insimul/tests/quest_trade_test.gd`** (`npm run test:ui-quest-trade`,
  via `run_quest_trade_headless.sh`) runs the shared quest + trade matrices
  (`conformance/ui/{quest-journal-cases,trade-cases}.json`) against
  `InsimulQuestJournalModel` and `InsimulTradeModel`, plus the state-location
  invariant, the real-quest-system binding, and the view-models behind the
  ahead-of-corpus panels. Same staging discipline as the registry gate.
- **`addons/insimul/tests/dialogue_menu_save_test.gd`**
  (`npm run test:ui-dialogue-menu-save`, via `run_dialogue_menu_save_headless.sh`)
  runs the shared dialogue + pause-menu + save-slot matrices
  (`conformance/ui/{chat-cases,pause-menu-cases,save-slot-cases}.json`) against
  `InsimulChatModel`, `InsimulPauseMenuModel` and `InsimulSaveSlotModel`, and then
  the Controls themselves in a real tree: the dialogue panel driven by a stub
  streaming service (chunks accumulating, the input locking for the length of a
  turn, TTS + lip-sync firing once on the settled line and never on an errored one,
  a KB fact asserted exactly once, the transcript landing in `save.conversations`
  and updating in place), the ESC menu regating its tab bar and resolving its tab
  bodies through the registry — including a body the band-111 gate takes away, with
  the diagnostic that says which module did it — the menu shell, the save/load rows
  (the corrupted-envelope messaging as RENDERED text, Load disabled, Save not) and
  the main-menu Continue gate. Same staging discipline as the other two.
- **`tools/verify-ui/check-ui.mjs`** (`npm run check`) needs nothing but Node, so
  the parity claims still have a gate on a box with no Godot: the manifest and the
  corpus document the same **pinned** panels (both ways), the ahead-of-corpus tier
  accounts for itself (a reason, no overlap with the corpus, a `gate_note` when
  ungated), a composite mounts panels that exist and never itself, every scene and
  every scene dependency is a real file, every gated module is in the activation
  table and is activated by some bundle, neither the registry nor a composite's
  script names a panel or a module, the token set matches the corpus (both ways),
  nothing in the UI calls into `InsimulCore`, every shipped ESC-menu tab has a body
  or a written reason it has none (never both, never neither), the shipped tab set
  is exactly the one the shared cases gate — in declaration order — and no resolver
  spells a panel key. Every check has a negative control under `--self-test`.
