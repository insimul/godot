class_name InsimulChatModel
extends RefCounted
## Dialogue / chat streaming view-model (US-GU3).
##
## The Godot mirror of the engine-neutral dialogue contract
## (packages/core/src/ui/chat-model.ts). Drives the streaming SDK's turn lifecycle:
## a player line opens a turn, response CHUNKS accumulate into the in-flight NPC
## bubble, ACTION triggers (applied to the KB by the panel) are recorded, and
## complete()/fail() close the turn. The finished transcript projects into the
## save.conversations (ConversationSummary.recentTurns) shape.
##
## TTS + insimul_lip_sync are PANEL hooks fed from last_npc_text() on complete().
## Shared cases: packages/core/conformance/ui/chat-cases.json.

var character_id := ""
var character_name := ""

var _messages: Array = []          # [{ role, text, streaming?, error? }]
var _actions: Array = []           # [{ name, args?, factToAssert? }]
var _streaming := false
var _stream_index := -1
var _turn_count := 0


func _init(char_id: String = "", char_name: String = "") -> void:
	character_id = char_id
	character_name = char_name if char_name != "" else char_id


## Seed the NPC's opening line (context greeting) — not a streamed turn.
func greeting(text: String) -> void:
	if text.is_empty():
		return
	_messages.append({"role": "npc", "text": text})


## Open a new turn with the player's line and an empty in-flight NPC bubble.
## Rejected (returns false) while a turn is already streaming.
func begin_user_turn(text: String) -> bool:
	if _streaming:
		return false
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return false
	_messages.append({"role": "player", "text": trimmed})
	_messages.append({"role": "npc", "text": "", "streaming": true})
	_stream_index = _messages.size() - 1
	_streaming = true
	return true


## Append a streamed chunk to the in-flight NPC bubble. No-op when idle.
func append_chunk(text: String) -> void:
	if not _streaming or _stream_index < 0:
		return
	_messages[_stream_index]["text"] = String(_messages[_stream_index]["text"]) + text


## Record an action the stream triggered (the panel applies it to the KB).
func trigger_action(action: Dictionary) -> void:
	_actions.append(action.duplicate(true))


## Close the in-flight turn (a done event). full_text, when non-null, replaces the
## accumulated bubble text. Returns false when no turn is in flight.
func complete_turn(full_text: Variant = null) -> bool:
	if not _streaming or _stream_index < 0:
		return false
	var bubble: Dictionary = _messages[_stream_index]
	if full_text != null:
		bubble["text"] = String(full_text)
	bubble.erase("streaming")
	_streaming = false
	_stream_index = -1
	_turn_count += 1
	return true


## Fail the in-flight turn (stream error / watchdog) — renders an error bubble.
func fail_turn(error: String) -> bool:
	if not _streaming or _stream_index < 0:
		return false
	var bubble: Dictionary = _messages[_stream_index]
	bubble["text"] = "[Error: %s]" % error
	bubble["error"] = true
	bubble.erase("streaming")
	_streaming = false
	_stream_index = -1
	return true


func is_streaming() -> bool:
	return _streaming


## The whole transcript (including any in-flight / errored bubble), oldest first.
func message_list() -> Array:
	var out: Array = []
	for m in _messages:
		out.append((m as Dictionary).duplicate(true))
	return out


## Actions triggered so far (the panel diffs this to feed the KB).
func action_list() -> Array:
	var out: Array = []
	for a in _actions:
		out.append((a as Dictionary).duplicate(true))
	return out


## The current in-flight bubble text (for live rendering).
func streaming_text() -> String:
	if _stream_index >= 0:
		return String(_messages[_stream_index]["text"])
	return ""


## The last settled (non-streaming, non-error) NPC line — TTS / lip-sync source.
func last_npc_text() -> String:
	for i in range(_messages.size() - 1, -1, -1):
		var m: Dictionary = _messages[i]
		if String(m.get("role", "")) == "npc" and not m.has("streaming") and not m.has("error"):
			return String(m.get("text", ""))
	return ""


func completed_turn_count() -> int:
	return _turn_count


## Project the transcript into ConversationSummary.recentTurns form. In-flight and
## errored bubbles are excluded (only settled turns persist). timestamp stamps every
## emitted turn (caller-supplied so the projection stays deterministic).
func history(timestamp: String = "") -> Dictionary:
	var recent: Array = []
	for m in _messages:
		if m.has("streaming") or m.has("error"):
			continue
		recent.append({"role": String(m.get("role", "")), "content": String(m.get("text", "")), "timestamp": timestamp})
	return {"recentTurns": recent, "totalTurnCount": _turn_count}
