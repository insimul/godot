@tool
class_name InsimulV1Client
extends RefCounted
## Thin v1 REST client for the editor (US-GE1).
##
## Hand-written over the transport seam (the pattern the PRD calls for — like
## Unreal's), it mirrors packages/core/openapi/operations.json as the OPERATIONS
## table. The core operations resolver (packages/core/src/editor/operations.ts) and
## the conformance test (packages/core/src/editor/__tests__/operations.test.ts) pin
## this table to the generated spec — a drift in method or path fails CI. Resolves
## an operationId to its method + path and dispatches through an injected
## InsimulV1Transport, so the panels are testable headless against a mock.

## operationId -> { "method": String, "path": String }. MIRRORS
## packages/core/openapi/operations.json byte-for-byte on method + path — keep in
## sync (conformance-guarded). Regenerate the spec with `npm run codegen` and
## update this table in lock step.
const OPERATIONS := {
	"streamConversation": {"method": "POST", "path": "/api/conversation/stream"},
	"streamConversationAudio": {"method": "POST", "path": "/api/conversation/stream-audio"},
	"endConversation": {"method": "POST", "path": "/api/conversation/end"},
	"healthCheck": {"method": "GET", "path": "/api/conversation/health"},
	"listWorlds": {"method": "GET", "path": "/api/worlds"},
	"getWorldDetail": {"method": "POST", "path": "/api/worlds/detail"},
	"importWorld": {"method": "POST", "path": "/api/generation/import"},
	"startGenerationJob": {"method": "POST", "path": "/api/generation/jobs"},
	"getGenerationJob": {"method": "POST", "path": "/api/generation/jobs/status"},
	"streamGenerationJob": {"method": "POST", "path": "/api/generation/jobs/events"},
	"syncGenerationJob": {"method": "POST", "path": "/api/generation/jobs/sync"},
}

## operationIds the editor panels actively call (US-GE1 health + US-GE2 World
## Browser / Generation Console). Each MUST resolve in OPERATIONS — the conformance
## test checks it, and that this list equals core's USED_OPERATION_IDS.
const USED_OPERATIONS := [
	"healthCheck",
	"listWorlds",
	"getWorldDetail",
	"importWorld",
	"startGenerationJob",
	"getGenerationJob",
	"streamGenerationJob",
	"syncGenerationJob",
]

var _transport: InsimulV1Transport
var _base_url: String = ""


func _init(transport: InsimulV1Transport, base_url: String = "") -> void:
	_transport = transport
	_base_url = base_url.rstrip("/")


## Resolve an operationId to { "method", "path" }, or {} if it is unknown.
func resolve(operation_id: String) -> Dictionary:
	return OPERATIONS.get(operation_id, {})


## Dispatch `operation_id` with `token` + optional JSON `body`, delivering the
## response Dictionary { "code", "body" } to `on_done`. An unknown operation
## replies with code 0 (never fires a request).
func call_operation(operation_id: String, token: String, body: String, on_done: Callable) -> void:
	var op := resolve(operation_id)
	if op.is_empty():
		on_done.call({"code": 0, "body": "unknown operation: %s" % operation_id})
		return
	var headers := {"Content-Type": "application/json"}
	if token != "":
		headers["Authorization"] = "Bearer %s" % token
	var req := {
		"operationId": operation_id,
		"method": String(op["method"]),
		"url": _base_url + String(op["path"]),
		"headers": headers,
		"body": body,
	}
	_transport.request(req, on_done)
