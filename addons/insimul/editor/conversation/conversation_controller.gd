@tool
class_name InsimulConversationController
extends RefCounted
## In-editor Conversation Tester — teardown-safe stream controller (US-GE3).
##
## The dock owns one of these per active stream; dispose() flips `_disposed` so any
## stream frame that arrives AFTER teardown is DROPPED (no on_update fires, no state
## changes). So the dock's _exit_tree can dispose the controller with the guarantee
## that a late SSE frame from an editor-process stream can never touch a freed node —
## the same zombie-response guarantee InsimulJobPoller gives the Generation Console.
##
## Mirrors the ConversationController in
## packages/core/src/editor/conversation-tester.ts (the tested source of truth,
## conversation-tester.test.ts); driven headless by conversation_test.gd.

var _state: Dictionary
var _on_update: Callable
var _disposed := false


func _init(on_update: Callable, character_id: String = "") -> void:
	_on_update = on_update
	_state = InsimulConversationReducer.initial_state(character_id)


func current() -> Dictionary:
	return _state


func is_disposed() -> bool:
	return _disposed


## Apply a transition Callable(state) -> new_state; fires on_update on a real change.
## A no-op (dropped) after dispose.
func apply(transition: Callable) -> void:
	if _disposed:
		return
	var next: Dictionary = transition.call(_state)
	if next != _state:
		_state = next
		_on_update.call(next)


func send_player(text: String) -> void:
	apply(func(s): return InsimulConversationReducer.send_player(s, text))


func dispatch_event(ev: Dictionary) -> void:
	apply(func(s): return InsimulConversationReducer.reduce_event(s, ev))


## Feed one raw SSE payload; parses then dispatches (dropped after dispose).
func feed_raw(data: String) -> void:
	if _disposed:
		return
	var ev := InsimulConversationReducer.parse_event(data)
	if not ev.is_empty():
		dispatch_event(ev)


func stream_failed() -> void:
	apply(func(s): return InsimulConversationReducer.stream_failed(s))


func recorded(text: String, reasoning: String) -> void:
	apply(func(s): return InsimulConversationReducer.recorded(s, text, reasoning))


func end() -> void:
	apply(func(s): return InsimulConversationReducer.end(s))


## Tear down: no further apply/feed has any effect. Idempotent.
func dispose() -> void:
	_disposed = true
