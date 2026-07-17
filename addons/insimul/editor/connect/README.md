# Editor v1 client + session (US-GE1)

The backend-connection foundation for the in-editor panels (World Browser,
Generation Console, Conversation Tester — US-GE2/US-GE3). The editor gets its
**own** session, separate from the runtime autoload (`insimul_client.gd`): the game
talks to a server with its shipped provider settings; the editor talks to the
platform to browse worlds, run generators, and test conversations, and must not
share or leak the game's credentials.

## Files

- `v1_transport.gd` — `InsimulV1Transport`, the **mockable request seam** (abstract
  base). A concrete transport performs a request Dictionary
  (`{operationId, method, url, headers, body}`) and calls back `{code, body}`.
- `v1_mock_transport.gd` — `InsimulV1MockTransport`, an in-memory transport that
  records requests (`sent`) and replies from a FIFO queue (`enqueue(code, body)`),
  synchronously. Backs the headless logic tests.
- `v1_http_transport.gd` — `InsimulV1HttpTransport`, the real `HTTPRequest`-backed
  transport. Needs a live editor SceneTree, so it is **structurally checked only**
  (the lint) + the human end-to-end pass.
- `v1_client.gd` — `InsimulV1Client`, the thin client. Its `OPERATIONS` table
  mirrors `packages/core/openapi/operations.json`; `resolve(id)` +
  `call_operation(id, token, body, on_done)` build and dispatch the request.
- `insimul_editor_session.gd` — `InsimulEditorSession`. Settings (base URL + token),
  token lifecycle (verify on login, clear on 401/403), `health` / `verify`, and
  `load_settings` / `save_settings`.

## Secret-storage rule (non-negotiable)

The editor session splits its two settings across two Godot stores by
sensitivity — this is the security contract the story enforces:

| Setting          | Key                          | Store            | Committed?                  |
| ---------------- | ---------------------------- | ---------------- | --------------------------- |
| Server URL       | `insimul/editor/server_url`  | `ProjectSettings`| **Yes** (`project.godot`)   |
| API token (secret) | `insimul/editor/api_token` | `EditorSettings` | **No** (per-machine editor) |

- The **server URL is non-secret and shared** — it lives in `ProjectSettings`, so
  it travels with the project and every teammate points at the same server.
- The **API token is a secret** — it lives ONLY in `EditorSettings`, Godot's
  per-machine editor config, which is **not** part of the project and is never
  committed to VCS. The token **never touches `ProjectSettings` or any project
  file.**

`save_settings()` writes the URL via `ProjectSettings.set_setting(...)` and the
token via the `EditorSettings` handle (`EditorInterface.get_editor_settings()`),
never the other way around. The guard
`packages/core/src/editor/__tests__/operations.test.ts` **statically** asserts the
token key never appears on a `ProjectSettings` line and is persisted only through
the `EditorSettings` handle — so a future edit that leaks the token into the
project file fails CI.

## Testing (logic tested; editor-coupled structurally checked)

- **Machine-runnable, bare box (`npm test`)** —
  `packages/core/src/editor/__tests__/operations.test.ts` +
  `editor-session.test.ts`. The operation-table conformance guard pins the
  GDScript `OPERATIONS` table + the core `V1_OPERATIONS` const to the generated
  `operations.json`; the secret-storage guard is the static check above; the
  reference `EditorSession` proves the login / 401 / health lifecycle over a mock
  transport (the same contract this GDScript session mirrors).
- **Godot end-to-end (merge gate)** — `connect_test.gd`
  (`run_connect_headless.sh`, SKIPs without a `godot` binary) drives the real
  GDScript client + session over `InsimulV1MockTransport`. The GDScript structural
  lint covers every `.gd` here on a bare box.
