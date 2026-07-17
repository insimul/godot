# Generation Console dock (US-GE2)

An in-editor dock for invoking the platform's generators as jobs and tracking their
progress, over the US-GE1 editor session. Progress arrives via SSE
(`streamGenerationJob`) with a **polling fallback** (`getGenerationJob`) for when the
editor can't hold a stream open; both funnel through the same reducer.

## Files

- `job_reducer.gd` — `InsimulJobReducer`, the transport-free **lifecycle state
  machine**: `initial_job` / `reduce` / `parse_job_event` (SSE frame) / `parse_job`
  (poll body) / `progress_percent` / `summarize`. A terminal job is **frozen** so
  the SSE and polling paths can overlap safely.
- `job_poller.gd` — `InsimulJobPoller`, the **polling fallback + teardown**: one
  poll in flight at a time; `dispose()` cancels the pending timer and drops a
  response that returns after teardown (no `on_update`, no next poll). Both the
  timer seam (a `Scheduler` with `set_timer`/`clear_timer`) and the request seam
  (a `fetch_job` `Callable`) are injected, so it is testable headless.
- `insimul_generation_console_dock.gd` — `InsimulGenerationConsoleDock`, the **UI**
  (`@tool` `Control`): a button + `ProgressBar` + log wired to the reducer/poller;
  it backs the poller's `Scheduler` with `Timer` nodes and **disposes the poller in
  `_exit_tree`** so an editor restart never orphans a timer or request. Structurally
  checked only.
- `generation_test.gd` / `run_generation_headless.sh` — the merge-gate GDScript leg
  (SKIPs without a `godot` binary), including the teardown path.

## Source of truth + tests

The engine-agnostic contract lives in
`packages/core/src/editor/generation-console.ts` (reducer) and `job-poller.ts`
(poller), tested on a bare box by `generation-console.test.ts` + `job-poller.test.ts`
(`npm test`). The GDScript here mirrors it. The **editor-restart safety** criterion
(no orphaned timers/requests) is pinned by `job-poller.test.ts` and mirrored in
`generation_test.gd`. See the package `VERIFICATION.md`.
