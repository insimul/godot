@tool
class_name InsimulV1MockTransport
extends InsimulV1Transport
## In-memory transport for headless tests (US-GE1).
##
## Records every request it is handed (`sent`) and replies from a FIFO queue of
## canned responses, invoking `on_done` SYNCHRONOUSLY so the session/client logic
## is testable straight-line with no real HTTP or SceneTree. Enqueue responses
## with enqueue(); an exhausted queue replies with code 0.

var sent: Array = []             # recorded request Dictionaries, in call order
var _responses: Array = []       # queued { "code": int, "body": String }


## Queue a canned response, returned (FIFO) by the next request().
func enqueue(code: int, body: String = "") -> void:
	_responses.append({"code": code, "body": body})


func request(req: Dictionary, on_done: Callable) -> void:
	sent.append(req)
	var res := {"code": 0, "body": ""}
	if not _responses.is_empty():
		res = _responses.pop_front()
	on_done.call(res)
