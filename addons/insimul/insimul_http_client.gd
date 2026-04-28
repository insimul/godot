class_name InsimulHttpClient
extends RefCounted
## HTTP/SSE transport for the Insimul conversation service.
## Sends requests via HTTPClient and parses Server-Sent Events responses.

signal text_chunk_received(chunk: InsimulTypes.TextChunk)
signal audio_chunk_received(chunk: InsimulTypes.AudioChunk)
signal facial_data_received(data: InsimulTypes.FacialData)
signal action_trigger_received(action: InsimulTypes.ActionTrigger)
signal transcript_received(text: String)
signal error_received(message: String)
signal stream_completed()

var _server_url: String = ""
var _api_key: String = ""
var _http_request: HTTPRequest = null
var _sse_buffer: String = ""


func _init(server_url: String, api_key: String = "") -> void:
	_server_url = server_url.rstrip("/")
	_api_key = api_key


## Attach an HTTPRequest node to the given parent for making requests.
func setup(parent: Node) -> void:
	if _http_request != null:
		return
	_http_request = HTTPRequest.new()
	_http_request.use_threads = true
	parent.add_child(_http_request)


## Send a text conversation request and stream SSE response.
func send_text(session_id: String, character_id: String, world_id: String,
		text: String, language_code: String = "en") -> void:
	var body := JSON.stringify({
		"sessionId": session_id,
		"characterId": character_id,
		"worldId": world_id,
		"text": text,
		"languageCode": language_code,
	})
	_make_sse_request("/api/conversation/stream", body)


## Send an audio conversation request and stream SSE response.
func send_audio(session_id: String, character_id: String, world_id: String,
		audio_data: PackedByteArray, language_code: String = "en") -> void:
	# Build multipart form data
	var boundary := "InsimulBoundary%d" % randi()
	var body := PackedByteArray()

	# Session ID field
	body.append_array(_multipart_field(boundary, "sessionId", session_id))
	# Character ID field
	body.append_array(_multipart_field(boundary, "characterId", character_id))
	# World ID field
	body.append_array(_multipart_field(boundary, "worldId", world_id))
	# Language code field
	body.append_array(_multipart_field(boundary, "languageCode", language_code))
	# Audio file field
	body.append_array(_multipart_file(boundary, "audio", "recording.webm", audio_data))
	# Closing boundary
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())

	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=%s" % boundary,
	])
	if _api_key != "":
		headers.append("Authorization: Bearer %s" % _api_key)

	_sse_buffer = ""
	_http_request.request_completed.connect(_on_request_completed, CONNECT_ONE_SHOT)
	_http_request.request_raw(
		_server_url + "/api/conversation/stream-audio",
		headers,
		HTTPClient.METHOD_POST,
		body
	)


## End the conversation session.
func end_session(session_id: String) -> void:
	var body := JSON.stringify({"sessionId": session_id})
	var headers := _build_json_headers()
	# Fire-and-forget; we don't need the response
	var http := HTTPRequest.new()
	_http_request.get_parent().add_child(http)
	http.request_completed.connect(func(_result, _code, _hdrs, _body): http.queue_free(), CONNECT_ONE_SHOT)
	http.request(_server_url + "/api/conversation/end", headers, HTTPClient.METHOD_POST, body)


## Check server health.
func health_check(callback: Callable) -> void:
	var http := HTTPRequest.new()
	_http_request.get_parent().add_child(http)
	http.request_completed.connect(func(_result: int, response_code: int, _hdrs: PackedStringArray, body: PackedByteArray):
		var response := InsimulTypes.HealthCheckResponse.new()
		if response_code == 200:
			var json := JSON.parse_string(body.get_string_from_utf8())
			if json is Dictionary:
				response.healthy = json.get("healthy", false)
				response.version = json.get("version", "")
				response.services = json.get("services", {})
		callback.call(response)
		http.queue_free()
	, CONNECT_ONE_SHOT)
	http.request(_server_url + "/api/conversation/health", _build_json_headers())


# ── Internal ─────────────────────────────────────────────────────────────────

func _make_sse_request(path: String, body: String) -> void:
	var headers := _build_json_headers()
	_sse_buffer = ""
	_http_request.request_completed.connect(_on_request_completed, CONNECT_ONE_SHOT)
	_http_request.request(_server_url + path, headers, HTTPClient.METHOD_POST, body)


func _build_json_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _api_key != "":
		headers.append("Authorization: Bearer %s" % _api_key)
	return headers


func _on_request_completed(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		error_received.emit("Server returned %d" % response_code)
		stream_completed.emit()
		return
	_parse_sse_body(body.get_string_from_utf8())
	stream_completed.emit()


func _parse_sse_body(text: String) -> void:
	_sse_buffer += text
	var lines := _sse_buffer.split("\n")
	_sse_buffer = ""

	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed == "" or not trimmed.begins_with("data: "):
			continue
		var data := trimmed.substr(6)  # Remove "data: " prefix
		if data == "[DONE]":
			return
		var json = JSON.parse_string(data)
		if json is Dictionary:
			_dispatch_event(json)


func _dispatch_event(event: Dictionary) -> void:
	var event_type: String = event.get("type", "")
	match event_type:
		"text":
			var chunk := InsimulTypes.TextChunk.new()
			chunk.text = event.get("text", "")
			chunk.is_final = event.get("isFinal", false)
			text_chunk_received.emit(chunk)
		"audio":
			var chunk := InsimulTypes.AudioChunk.new()
			chunk.data = Marshalls.base64_to_raw(event.get("data", ""))
			chunk.encoding = int(event.get("encoding", 0))
			chunk.sample_rate = int(event.get("sampleRate", 16000))
			chunk.duration_ms = int(event.get("durationMs", 0))
			audio_chunk_received.emit(chunk)
		"facial":
			var facial := InsimulTypes.FacialData.new()
			var viseme_array: Array = event.get("visemes", [])
			for v in viseme_array:
				if v is Dictionary:
					var viseme := InsimulTypes.Viseme.new()
					viseme.phoneme = v.get("phoneme", "")
					viseme.weight = float(v.get("weight", 0.0))
					viseme.duration_ms = int(v.get("durationMs", 0))
					facial.visemes.append(viseme)
			facial_data_received.emit(facial)
		"transcript":
			transcript_received.emit(event.get("text", ""))
		"error":
			error_received.emit(event.get("message", "Unknown error"))


func _multipart_field(boundary: String, name: String, value: String) -> PackedByteArray:
	var part := "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, name, value]
	return part.to_utf8_buffer()


func _multipart_file(boundary: String, name: String, filename: String, data: PackedByteArray) -> PackedByteArray:
	var header := "--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n" % [boundary, name, filename]
	var result := header.to_utf8_buffer()
	result.append_array(data)
	result.append_array("\r\n".to_utf8_buffer())
	return result
