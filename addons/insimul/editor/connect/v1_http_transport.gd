@tool
class_name InsimulV1HttpTransport
extends InsimulV1Transport
## HTTPRequest-backed transport for the editor v1 client (US-GE1).
##
## The real request seam used inside the editor: each call spins up a one-shot
## HTTPRequest child under the provided parent Node, performs the request, and
## delivers { "code", "body" } to `on_done`. It needs a live SceneTree to host the
## HTTPRequest, so the headless logic tests use InsimulV1MockTransport instead and
## this file is covered by the GDScript structural lint + the human end-to-end pass
## (VERIFICATION.md), matching the addon's "logic tested, editor-coupled
## structurally checked" split.

var _parent: Node = null


func _init(parent: Node) -> void:
	_parent = parent


func request(req: Dictionary, on_done: Callable) -> void:
	var http := HTTPRequest.new()
	_parent.add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		on_done.call({"code": code, "body": body.get_string_from_utf8()})
		http.queue_free()
	, CONNECT_ONE_SHOT)
	var headers := PackedStringArray()
	for key in req.get("headers", {}):
		headers.append("%s: %s" % [key, req["headers"][key]])
	var verb := String(req.get("method", "GET"))
	var body := String(req.get("body", ""))
	http.request(String(req.get("url", "")), headers, _http_method(verb), body)


func _http_method(verb: String) -> int:
	match verb.to_upper():
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		"PATCH":
			return HTTPClient.METHOD_PATCH
		_:
			return HTTPClient.METHOD_GET
