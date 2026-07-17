@tool
class_name InsimulEditorSession
extends RefCounted
## Editor-side session: settings, token lifecycle, health/verify (US-GE1).
##
## The editor panels get their OWN session, distinct from the runtime autoload
## (InsimulClient): the editor talks to the platform to browse worlds, run
## generators, and test conversations, and it must not share the game's provider
## settings. This owns the base URL + auth token, the token lifecycle (verify on
## login, clear on 401/403), and the health probe, all over an injected
## InsimulV1Transport so the logic is testable headless (connect_test.gd).
##
## SECRET-STORAGE RULE (enforced + tested):
##   - The server URL is NON-SECRET, shared, and stored in ProjectSettings
##     ("insimul/editor/server_url"), so it travels with the project (project.godot)
##     and every teammate hits the same server.
##   - The API token is a SECRET and stored ONLY in EditorSettings
##     ("insimul/editor/api_token") — a PER-MACHINE editor store that is NOT part of
##     the project and is never committed. The token NEVER touches ProjectSettings
##     or any project file.
## The operations conformance guard statically verifies the token key never appears
## on a ProjectSettings line and is persisted only via the EditorSettings handle.
## See connect/README.md.

const _URL_SETTING := "insimul/editor/server_url"
const _TOKEN_SETTING := "insimul/editor/api_token"
const _DEFAULT_URL := "http://localhost:8080"

var base_url: String = _DEFAULT_URL
var _token: String = ""
var _client: InsimulV1Client


func _init(transport: InsimulV1Transport = null) -> void:
	var t: InsimulV1Transport = transport if transport != null else InsimulV1MockTransport.new()
	_client = InsimulV1Client.new(t, base_url)


## The in-memory token (empty when unauthenticated). Persisted only via
## EditorSettings by save_settings().
func get_token() -> String:
	return _token


func is_authenticated() -> bool:
	return _token != ""


## Store `token` and verify it against the server. On a 2xx the token is kept and
## the session is authenticated; on a 401/403 the token is CLEARED (an invalid
## credential is never left persisted) and the failure is reported to `on_done`.
func login(token: String, on_done: Callable) -> void:
	_token = token
	verify(func(res: Dictionary):
		var code := int(res.get("code", 0))
		if code == 401 or code == 403:
			_token = ""
		on_done.call(res)
	)


## Clear the stored token.
func logout() -> void:
	_token = ""


## Dispatch a v1 operation through the session's client with the current token +
## optional JSON `body`, delivering the raw { "code", "body" } response to `on_done`.
## The World Browser / Generation Console docks (US-GE2) and the conversation tester
## (US-GE3) call the API through here so they never touch the transport directly.
func call_operation(operation_id: String, body: String, on_done: Callable) -> void:
	_client.call_operation(operation_id, _token, body, on_done)


## Verify the current token by probing the health endpoint.
func verify(on_done: Callable) -> void:
	health(on_done)


## Probe server liveness via the healthCheck operation, delivering a result
## Dictionary { "ok": bool, "code": int, "healthy"?: bool, "error"?: String }.
func health(on_done: Callable) -> void:
	_client.call_operation("healthCheck", _token, "", func(res: Dictionary):
		on_done.call(_interpret(res))
	)


func _interpret(res: Dictionary) -> Dictionary:
	var code := int(res.get("code", 0))
	var ok := code >= 200 and code < 300
	var out := {"ok": ok, "code": code}
	if ok:
		var parsed = JSON.parse_string(String(res.get("body", "")))
		if parsed is Dictionary and parsed.has("healthy"):
			out["healthy"] = bool(parsed["healthy"])
	else:
		out["error"] = "server returned %d" % code
	return out


# ── Settings persistence (editor-only; secret in EditorSettings) ───────────────

## Load base_url from ProjectSettings and the token from EditorSettings. A no-op for
## whichever store is unavailable (e.g. a plain --headless SceneTree run has no
## EditorSettings), so the logic tests never depend on the editor singletons.
func load_settings() -> void:
	if ProjectSettings.has_setting(_URL_SETTING):
		base_url = String(ProjectSettings.get_setting(_URL_SETTING, _DEFAULT_URL))
	var editor_settings := _editor_settings()
	if editor_settings != null and editor_settings.has_setting(_TOKEN_SETTING):
		_token = String(editor_settings.get_setting(_TOKEN_SETTING))


## Persist base_url to ProjectSettings (the project file) and the token to
## EditorSettings (per-machine, never committed). The URL is non-secret; the token
## is written ONLY through the EditorSettings handle.
func save_settings() -> void:
	ProjectSettings.set_setting(_URL_SETTING, base_url)
	ProjectSettings.save()
	var editor_settings := _editor_settings()
	if editor_settings != null:
		editor_settings.set_setting(_TOKEN_SETTING, _token)


## The per-machine EditorSettings store, or null outside a running editor.
func _editor_settings():
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		return EditorInterface.get_editor_settings()
	return null
