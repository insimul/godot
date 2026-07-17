# NPC Conversation Tester dock (US-GE3)

An in-editor dock for testing a world's NPC conversations without leaving Godot, over
the US-GE1 editor session. Pick a character from imported world data, type a line, and
watch the character response stream into a transcript — with a **recorded-reasoning
fallback** for when in-editor streaming misbehaves.

## Files

- `conversation_reducer.gd` — `InsimulConversationReducer`, the transport-free
  **character picker + transcript state machine**: `extract_characters` (from
  imported world data), `parse_event` (a `streamConversation` SSE frame), and the
  reducer (`send_player` / `reduce_event` / `stream_failed` / `recorded` / `end`). A
  closed turn is frozen (events with no open turn are ignored).
- `conversation_controller.gd` — `InsimulConversationController`, the **teardown-safe
  stream wrapper**: `dispose()` flips a `_disposed` flag so a stream frame arriving
  **after** teardown is dropped (no `on_update`, no state change) — the same
  zombie-response guarantee `InsimulJobPoller` gives the Generation Console.
- `insimul_conversation_tester_dock.gd` — `InsimulConversationTesterDock`, the **UI**
  (`@tool` `Control`): an `OptionButton` picker + a transcript `RichTextLabel` +
  input/Send wired to the reducer/controller, dispatching `streamConversation` /
  `endConversation` through `InsimulEditorSession`. It **disposes the controller in
  `_exit_tree`**, so an editor restart never lets a late SSE frame touch a freed node.
  Structurally checked only.
- `conversation_test.gd` / `run_conversation_headless.sh` — the merge-gate GDScript
  leg (SKIPs without a `godot` binary), including the recorded-fallback auto-switch
  and the controller teardown path.

## Constraints (editor-process streaming)

- **The editor session's transport is request/response, not a persistent SSE
  socket.** The runtime autoload (`insimul_client.gd` / `insimul_http_client.gd`)
  holds a real streaming socket in the *game*; the editor dock reads the SSE body
  from a single `streamConversation` request and feeds its `data:` frames through the
  same reducer. So the transcript is **near-streaming** (frame-by-frame as the body
  arrives), not token-by-token low-latency like the runtime.
- **PIE-style recorded-reasoning fallback.** If in-editor streaming misbehaves — a
  non-2xx response, or a stream error frame on a live stream — the dock calls
  `controller.stream_failed()` and fills the turn from a **recorded reasoning trace**
  instead of failing the conversation. This matches the other engines' decision where
  the editor-process constraint is shared: prefer a recorded trace to a broken live
  stream. The first error auto-switches to the recorded mode; an error while already
  in the fallback is a hard error.
- **Secrets never leak.** The dock uses the editor session's token
  (`EditorSettings`, never a project file) — see `editor/connect/README.md`.

## Source of truth + tests

The engine-agnostic contract lives in
`packages/core/src/editor/conversation-tester.ts`, tested on a bare box by
`conversation-tester.test.ts` (`npm test`): the picker, the SSE-frame parser, the
transcript reducer over a mocked stream, the recorded-reasoning fallback auto-switch,
and the controller teardown (a frame after dispose is dropped). The GDScript here
mirrors it. See the package `VERIFICATION.md` for the human two-turn checklist.
