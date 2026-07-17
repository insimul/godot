@tool
class_name InsimulV1Transport
extends RefCounted
## Transport seam for the editor v1 client (US-GE1).
##
## The mockable request seam that keeps the editor panels testable headless: the
## client (InsimulV1Client) resolves an operation to a request Dictionary and hands
## it here; a concrete transport performs it and calls `on_done` with a response
## Dictionary { "code": int, "body": String }. The real transport
## (InsimulV1HttpTransport) drives an HTTPRequest; the test transport
## (InsimulV1MockTransport) returns canned responses synchronously. This base is
## abstract — subclasses override request().


## Perform the request `req` (keys: operationId, method, url, headers, body) and
## invoke `on_done` with a response Dictionary { "code": int, "body": String }.
func request(_req: Dictionary, _on_done: Callable) -> void:
	push_error("InsimulV1Transport.request() is abstract — use a concrete transport")
