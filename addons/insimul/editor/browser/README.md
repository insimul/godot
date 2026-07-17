# World Browser dock (US-GE2)

An in-editor dock for browsing the platform's worlds and pulling them into the
generation pipeline. It runs over the US-GE1 editor session
(`connect/insimul_editor_session.gd`) — no game credentials, no runtime autoload.

## Files

- `world_compat.gd` — `InsimulWorldCompat`, the compatibility badge: compares a
  world's save-format version against the editor's `SUPPORTED_SAVE_FORMAT` (kept in
  sync with `SAVE_FILE_VERSION`) → `compatible` / `warning` / `incompatible`.
- `world_browser_model.gd` — `InsimulWorldBrowserModel`, the **logic layer**:
  parses `listWorlds` / `importWorld` bodies, drives the list + selection reducer
  (`load_start` / `load_success` / `load_error` / `select`), builds the open-in-web
  URL, and summarizes the Import/Sync dry-run report. A `RefCounted` with no
  `Control` dependency, so it is testable headless.
- `insimul_world_browser_dock.gd` — `InsimulWorldBrowserDock`, the **UI** (`@tool`
  `Control`): a thin view that wires an `ItemList` + labels + buttons (Refresh,
  Import dry-run, Sync, Open-in-Web) to the model and dispatches operations through
  the session. Structurally checked only (needs a running editor).
- `browser_test.gd` / `run_browser_headless.sh` — the merge-gate GDScript leg
  (SKIPs without a `godot` binary).

## Source of truth + tests

The engine-agnostic contract lives in
`packages/core/src/editor/world-browser.ts` and is tested on a bare box by
`world-browser.test.ts` (`npm test`). The GDScript here mirrors it; `browser_test.gd`
is the Godot confirmation at the merge gate. See the package `VERIFICATION.md`
("World Browser + Generation Console docks (US-GE2)").
