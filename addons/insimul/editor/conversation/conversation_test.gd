# conversation_test.gd — the Godot headless leg of the Conversation Tester gate
# (US-GE3), exercising the LOGIC LAYER (InsimulConversationReducer +
# InsimulConversationController) over a mocked stream: the character picker, SSE
# frame parsing, the transcript reducer, the recorded-reasoning fallback auto-switch,
# and the controller teardown (a frame arriving after dispose is dropped).
#
# The dock UI (insimul_conversation_tester_dock.gd) needs a running editor and is
# only structurally checked. The machine-runnable source of truth is
# packages/core/src/editor/conversation-tester.ts + its .test.ts (bare box, npm
# test); this file is the end-to-end Godot confirmation for the merge gate. When NO
# `godot` binary is present the runner SKIPs.
#
#   godot --headless -s addons/insimul/editor/conversation/conversation_test.gd
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_test_picker()
	_test_parse_event()
	_test_transcript_stream()
	_test_recorded_fallback()
	_test_controller_teardown()
	_finish()


func _finish() -> void:
	print("-----------------------------------------------------------")
	print("[insimul-conversation] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _test_picker() -> void:
	var world := {
		"characters": [
			{"characterId": "c1", "firstName": "Ada", "lastName": "Vance", "occupation": "smith"},
			{"id": "c2", "name": "Bram the Baker"},
			{"firstName": "NoId"},
		],
	}
	var chars := InsimulConversationReducer.extract_characters(world)
	_report("picker drops entries without an id", chars.size() == 2, "%d" % chars.size())
	_report("picker joins first+last name", String(chars[0].get("name", "")) == "Ada Vance", "%s" % chars[0])
	_report("picker keeps explicit name", String(chars[1].get("name", "")) == "Bram the Baker", "%s" % chars[1])


func _test_parse_event() -> void:
	var t := InsimulConversationReducer.parse_event('{"type":"text","text":"Hi","isFinal":true}')
	_report("parse text frame", String(t.get("kind", "")) == "text" and t.get("is_final", false) == true, "%s" % t)
	var e := InsimulConversationReducer.parse_event('{"type":"error","message":"boom"}')
	_report("parse error frame", String(e.get("kind", "")) == "error", "%s" % e)
	_report("blank frame -> empty", InsimulConversationReducer.parse_event("  ").is_empty(), "")
	_report("unknown type -> empty", InsimulConversationReducer.parse_event('{"type":"weird"}').is_empty(), "")


func _test_transcript_stream() -> void:
	var s := InsimulConversationReducer.initial_state("c1")
	s = InsimulConversationReducer.send_player(s, "Hello")
	_report("send_player opens two turns", (s.get("turns", []) as Array).size() == 2 and String(s.get("status", "")) == "streaming", "%s" % s.get("status"))
	s = InsimulConversationReducer.reduce_event(s, {"kind": "reasoning", "text": "considering"})
	s = InsimulConversationReducer.reduce_event(s, {"kind": "text", "text": "Well "})
	s = InsimulConversationReducer.reduce_event(s, {"kind": "text", "text": "met.", "is_final": true})
	var turn: Dictionary = (s.get("turns", []) as Array)[1]
	_report("text chunks append + final closes", String(turn.get("text", "")) == "Well met." and turn.get("streaming", true) == false, "%s" % turn)
	_report("reasoning captured", String(turn.get("reasoning", "")) == "considering", "%s" % turn)
	_report("status awaiting after final", String(s.get("status", "")) == "awaiting", "%s" % s.get("status"))
	# Events after the turn closes are ignored (no open turn).
	var after := InsimulConversationReducer.reduce_event(s, {"kind": "text", "text": "stray"})
	_report("event after close ignored", after == s, "")


func _test_recorded_fallback() -> void:
	var s := InsimulConversationReducer.initial_state("c1")
	s = InsimulConversationReducer.send_player(s, "Hi")
	s = InsimulConversationReducer.reduce_event(s, {"kind": "error", "error": "stalled"})
	_report("first error auto-switches to recorded", String(s.get("status", "")) == "recording" and InsimulConversationReducer.is_recorded_fallback(s), "%s" % s.get("status"))
	s = InsimulConversationReducer.recorded(s, "Greetings.", "recorded trace")
	var turn: Dictionary = (s.get("turns", []) as Array)[1]
	_report("recorded completes the turn", String(turn.get("text", "")) == "Greetings." and turn.get("from_recording", false) == true, "%s" % turn)
	# A second error while already in the fallback is a hard error.
	var s2 := InsimulConversationReducer.send_player(InsimulConversationReducer.initial_state("c1"), "Hi")
	s2 = InsimulConversationReducer.reduce_event(s2, {"kind": "error", "error": "first"})
	s2 = InsimulConversationReducer.reduce_event(s2, {"kind": "error", "error": "again"})
	_report("second error is a hard error", String(s2.get("status", "")) == "error" and String(s2.get("error", "")) == "again", "%s" % s2)


func _test_controller_teardown() -> void:
	var seen: Array = []
	var ctrl := InsimulConversationController.new(func(s): seen.append(s), "c1")
	ctrl.send_player("Hi")
	ctrl.feed_raw('{"type":"text","text":"Wel"}')
	_report("two updates before dispose", seen.size() == 2, "%d" % seen.size())
	ctrl.dispose()
	# A zombie SSE frame arrives after teardown — it must be dropped entirely.
	ctrl.feed_raw('{"type":"text","text":"come","isFinal":true}')
	ctrl.end()
	_report("late frame dropped (no update)", seen.size() == 2, "%d" % seen.size())
	_report("late chunk never applied", String((ctrl.current().get("turns", []) as Array)[1].get("text", "")) == "Wel", "")
	ctrl.dispose() # idempotent
	_report("dispose idempotent", ctrl.is_disposed(), "")


func _report(name: String, ok: bool, detail: String) -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", name, ("" if detail.is_empty() else "  " + detail)])
	if ok:
		_pass += 1
	else:
		_fail += 1
