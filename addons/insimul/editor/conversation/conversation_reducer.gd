@tool
class_name InsimulConversationReducer
extends RefCounted
## In-editor NPC Conversation Tester — transcript reducer + character picker (US-GE3).
##
## The pure, transport-free heart of the Conversation Tester dock: it extracts the
## pickable characters from imported world data, parses a streamConversation SSE
## frame into an event, and folds a streaming character response into a running
## transcript. It also owns the PIE-style RECORDED-REASONING FALLBACK — if the
## editor-process streaming misbehaves (a stream error), the tester auto-switches to
## a recorded reasoning trace rather than failing the conversation.
##
## Mirrors packages/core/src/editor/conversation-tester.ts (the tested source of
## truth, conversation-tester.test.ts); driven headless by conversation_test.gd
## (merge-gate GUT) and covered by the structural lint. The dock UI
## (insimul_conversation_tester_dock.gd) is a thin view over these calls and the
## teardown-safe controller.

## Turn Dictionary shape:
##   { "role": "player"|"character", "text": String, "reasoning": String,
##     "actions": Array[{ "action_type", "target_id" }], "streaming": bool,
##     "from_recording": bool }
## State Dictionary shape:
##   { "character_id": String, "turns": Array, "status": String, "mode": String,
##     "error": String }
## status is "idle"|"streaming"|"recording"|"awaiting"|"ended"|"error";
## mode is "streaming"|"recorded".


# ── Character picker ──────────────────────────────────────────────────────────

## Extract the pickable characters from imported world data (a parsed Dictionary,
## world-export shape { "characters": [...] }). Each option is
## { "id", "name", "occupation" }. Entries without a characterId/id are dropped; the
## name falls back to firstName+lastName, then to the id.
static func extract_characters(world_data) -> Array:
	var out: Array = []
	if not (world_data is Dictionary):
		return out
	var raw = world_data.get("characters", null)
	if not (raw is Array):
		return out
	for entry in raw:
		if not (entry is Dictionary):
			continue
		var id := String(entry.get("characterId", entry.get("id", "")))
		if id == "":
			continue
		out.append({
			"id": id,
			"name": _character_name(entry, id),
			"occupation": String(entry.get("occupation", "")),
		})
	return out


static func _character_name(o: Dictionary, fallback: String) -> String:
	var name := String(o.get("name", ""))
	if name != "":
		return name
	var parts: Array = []
	var first := String(o.get("firstName", ""))
	var last := String(o.get("lastName", ""))
	if first != "":
		parts.append(first)
	if last != "":
		parts.append(last)
	if parts.is_empty():
		return fallback
	return " ".join(parts)


## Parse a getWorldDetail / world-export body then extract its characters.
static func parse_world_characters(body: String) -> Array:
	var parsed = JSON.parse_string(body)
	return extract_characters(parsed)


# ── SSE frame -> event ────────────────────────────────────────────────────────

## Parse one SSE data payload into an event Dictionary, or {} for a blank/keepalive
## frame, bad JSON, or an unknown type. Event shape:
##   { "kind": "text"|"reasoning"|"action"|"error"|"done", ... }
static func parse_event(data: String) -> Dictionary:
	var trimmed := data.strip_edges()
	if trimmed == "":
		return {}
	var parsed = JSON.parse_string(trimmed)
	if not (parsed is Dictionary):
		return {}
	var type := String(parsed.get("type", ""))
	match type:
		"text":
			return {
				"kind": "text",
				"text": String(parsed.get("text", "")),
				"is_final": parsed.get("isFinal", false) == true,
			}
		"reasoning":
			return {"kind": "reasoning", "text": String(parsed.get("text", ""))}
		"action":
			return {
				"kind": "action",
				"action_type": String(parsed.get("actionType", parsed.get("action", ""))),
				"target_id": String(parsed.get("targetId", "")),
			}
		"error":
			return {"kind": "error", "error": String(parsed.get("message", parsed.get("error", "stream error")))}
		"done", "end", "complete":
			return {"kind": "done"}
		_:
			return {}


# ── Transcript reducer ────────────────────────────────────────────────────────

static func initial_state(character_id: String = "") -> Dictionary:
	return {
		"character_id": character_id, "turns": [], "status": "idle",
		"mode": "streaming", "error": "",
	}


static func _empty_character_turn() -> Dictionary:
	return {
		"role": "character", "text": "", "reasoning": "", "actions": [],
		"streaming": true, "from_recording": false,
	}


static func _last_turn(state: Dictionary):
	var turns: Array = state.get("turns", [])
	if turns.is_empty():
		return null
	return turns[turns.size() - 1]


## The currently-open (streaming) character turn, or null.
static func open_turn(state: Dictionary):
	var last = _last_turn(state)
	if last is Dictionary and String(last.get("role", "")) == "character" and last.get("streaming", false):
		return last
	return null


static func is_recorded_fallback(state: Dictionary) -> bool:
	return String(state.get("mode", "")) == "recorded"


## Replace the last turn with `next`, returning a new turns Array.
static func _with_last_turn(state: Dictionary, next: Dictionary) -> Array:
	var turns: Array = (state.get("turns", []) as Array).duplicate()
	turns[turns.size() - 1] = next
	return turns


## Append a player turn + a fresh streaming character turn.
static func send_player(state: Dictionary, text: String) -> Dictionary:
	if String(state.get("status", "")) == "ended":
		return state
	var turns: Array = (state.get("turns", []) as Array).duplicate()
	turns.append({
		"role": "player", "text": text, "reasoning": "", "actions": [],
		"streaming": false, "from_recording": false,
	})
	turns.append(_empty_character_turn())
	var next := state.duplicate()
	next["turns"] = turns
	next["status"] = "streaming"
	next["mode"] = "streaming"
	next["error"] = ""
	return next


## Fold one stream event Dictionary into the open character turn.
static func reduce_event(state: Dictionary, ev: Dictionary) -> Dictionary:
	var open = open_turn(state)
	if not (open is Dictionary):
		return state
	var kind := String(ev.get("kind", ""))
	match kind:
		"text":
			var turn := (open as Dictionary).duplicate()
			turn["text"] = String(open.get("text", "")) + String(ev.get("text", ""))
			var final := ev.get("is_final", false) == true
			turn["streaming"] = not final
			var next := state.duplicate()
			next["turns"] = _with_last_turn(state, turn)
			next["status"] = "awaiting" if final else "streaming"
			return next
		"reasoning":
			var turn := (open as Dictionary).duplicate()
			turn["reasoning"] = String(ev.get("text", ""))
			var next := state.duplicate()
			next["turns"] = _with_last_turn(state, turn)
			return next
		"action":
			var turn := (open as Dictionary).duplicate()
			var actions: Array = (open.get("actions", []) as Array).duplicate()
			actions.append({
				"action_type": String(ev.get("action_type", "")),
				"target_id": String(ev.get("target_id", "")),
			})
			turn["actions"] = actions
			var next := state.duplicate()
			next["turns"] = _with_last_turn(state, turn)
			return next
		"done":
			var turn := (open as Dictionary).duplicate()
			turn["streaming"] = false
			var next := state.duplicate()
			next["turns"] = _with_last_turn(state, turn)
			next["status"] = "awaiting"
			return next
		"error":
			# First error on a live stream -> recorded fallback, not a hard error.
			if String(state.get("mode", "")) == "streaming":
				var next := state.duplicate()
				next["mode"] = "recorded"
				next["status"] = "recording"
				return next
			var turn := (open as Dictionary).duplicate()
			turn["streaming"] = false
			var hard := state.duplicate()
			hard["turns"] = _with_last_turn(state, turn)
			hard["status"] = "error"
			hard["error"] = String(ev.get("error", "stream error"))
			return hard
		_:
			return state


## Force the recorded-reasoning fallback (editor-process streaming misbehaved).
static func stream_failed(state: Dictionary) -> Dictionary:
	var open = open_turn(state)
	if not (open is Dictionary):
		return state
	var next := state.duplicate()
	next["mode"] = "recorded"
	next["status"] = "recording"
	return next


## Complete the open character turn from a recorded reasoning trace.
static func recorded(state: Dictionary, text: String, reasoning: String) -> Dictionary:
	var last = _last_turn(state)
	if not (last is Dictionary) or String(last.get("role", "")) != "character":
		return state
	var turn := (last as Dictionary).duplicate()
	turn["text"] = text
	turn["reasoning"] = reasoning
	turn["streaming"] = false
	turn["from_recording"] = true
	var next := state.duplicate()
	next["turns"] = _with_last_turn(state, turn)
	next["status"] = "awaiting"
	next["mode"] = "recorded"
	return next


## Close the conversation.
static func end(state: Dictionary) -> Dictionary:
	var next := state.duplicate()
	next["status"] = "ended"
	return next
