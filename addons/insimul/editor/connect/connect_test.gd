# connect_test.gd — the Godot headless leg of the editor-connect gate (US-GE1),
# exercising the LOGIC LAYER (InsimulV1Client + InsimulEditorSession) over the
# InsimulV1MockTransport.
#
# The HTTP transport (v1_http_transport.gd) needs a live editor SceneTree, so it is
# only structurally checked; the client + session are transport-injected and fully
# testable here. The machine-runnable operation-table conformance + secret-storage
# guards live in packages/core/src/editor/__tests__/operations.test.ts (they run on
# a bare box under `npm test`); this file is the end-to-end Godot confirmation for
# the merge gate. When NO `godot` binary is present the runner SKIPs.
#
#   godot --headless -s addons/insimul/editor/connect/connect_test.gd
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_test_client_resolve()
	_test_client_unknown_operation()
	_test_health_ok()
	_test_login_success()
	_test_login_401_clears_token()
	_test_request_carries_auth_and_url()
	_finish()


func _finish() -> void:
	print("-----------------------------------------------------------")
	print("[insimul-connect] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _test_client_resolve() -> void:
	var client := InsimulV1Client.new(InsimulV1MockTransport.new())
	var op := client.resolve("healthCheck")
	_report("healthCheck resolves", String(op.get("method", "")) == "GET"
		and String(op.get("path", "")) == "/api/conversation/health", "%s" % op)
	for used in InsimulV1Client.USED_OPERATIONS:
		_report("used op '%s' resolves" % used, not client.resolve(String(used)).is_empty(), "")


func _test_client_unknown_operation() -> void:
	var transport := InsimulV1MockTransport.new()
	var client := InsimulV1Client.new(transport)
	var got := {}
	client.call_operation("noSuchOp", "", "", func(res: Dictionary): got = res)
	_report("unknown op replies code 0 without a request",
		int(got.get("code", -1)) == 0 and transport.sent.is_empty(), "%s" % got)


func _test_health_ok() -> void:
	var transport := InsimulV1MockTransport.new()
	transport.enqueue(200, '{"healthy": true}')
	var session := InsimulEditorSession.new(transport)
	var result := {}
	session.health(func(res: Dictionary): result = res)
	_report("health 200 -> ok + healthy",
		bool(result.get("ok", false)) and bool(result.get("healthy", false)), "%s" % result)


func _test_login_success() -> void:
	var transport := InsimulV1MockTransport.new()
	transport.enqueue(200, '{"healthy": true}')
	var session := InsimulEditorSession.new(transport)
	var result := {}
	session.login("good-token", func(res: Dictionary): result = res)
	_report("login 200 keeps the token", bool(result.get("ok", false))
		and session.is_authenticated() and session.get_token() == "good-token", "%s" % result)


func _test_login_401_clears_token() -> void:
	var transport := InsimulV1MockTransport.new()
	transport.enqueue(401, "unauthorized")
	var session := InsimulEditorSession.new(transport)
	var result := {}
	session.login("bad-token", func(res: Dictionary): result = res)
	_report("login 401 clears the token",
		not bool(result.get("ok", true)) and not session.is_authenticated()
		and session.get_token() == "", "%s" % result)


func _test_request_carries_auth_and_url() -> void:
	var transport := InsimulV1MockTransport.new()
	transport.enqueue(200, '{"healthy": true}')
	var client := InsimulV1Client.new(transport, "http://localhost:8080/")
	client.call_operation("healthCheck", "tok", "", func(_res: Dictionary): pass)
	var req: Dictionary = transport.sent[0] if not transport.sent.is_empty() else {}
	var headers: Dictionary = req.get("headers", {})
	_report("request URL joins base + path",
		String(req.get("url", "")) == "http://localhost:8080/api/conversation/health", "%s" % req.get("url", ""))
	_report("request carries bearer auth",
		String(headers.get("Authorization", "")) == "Bearer tok", "%s" % headers)


# ── helpers ──────────────────────────────────────────────────────────────────
func _report(name: String, ok: bool, detail: String) -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", name, ("" if detail.is_empty() else "  " + detail)])
	if ok:
		_pass += 1
	else:
		_fail += 1
