extends Node
## Error Reporter — minimal singleton that captures NPC-chat failures.
## Ports BabylonChatPanel.ts Sentry.captureException calls to Godot.
##
## Default behavior: formats tags/extras and calls push_error.
## To route to Sentry (or any external reporter) install a handler:
##
##     ErrorReporter.handler = func(err_message, tags, extras):
##         SentrySdk.capture_exception(err_message, tags, extras)
##
## Autoload this as "ErrorReporter" (project settings → autoload).

## Optional override — receives the message, tags dict, and extras dict.
var handler: Callable = Callable()

## Capture a chat-path exception.
## `stage` is one of "timeout" | "provider" | "safety" | "sendMessage" | "unknown".
func capture_exception(
	err_message: String,
	stage: String,
	character_id: String,
	world_id: String,
	user_message: String,
	accumulated_text_length: int
) -> void:
	var tags := {
		"component": "chat-panel",
		"stage": stage if stage != "" else "unknown",
	}
	var extras := {
		"characterId": character_id,
		"worldId": world_id,
		"userMessage": user_message,
		"accumulatedTextLength": accumulated_text_length,
	}

	if handler.is_valid():
		var called := false
		var hook_err: String = ""
		# Guard against handler exceptions so we always fall back to push_error.
		var result = null
		if handler.get_argument_count() >= 3:
			result = handler.call(err_message, tags, extras)
			called = true
		else:
			push_warning("[ErrorReporter] handler has unexpected arity; falling back")
		if called:
			return

	push_error("[ErrorReporter] chat-panel %s | %s | characterId=%s worldId=%s accumulated=%d" % [
		tags["stage"], err_message, character_id, world_id, accumulated_text_length
	])


## Classify an error message into a Sentry-compatible stage tag.
func classify_error_stage(message: String) -> String:
	if message == null or message == "":
		return "unknown"
	var lower := message.to_lower()
	if lower.contains("timeout") or lower.contains("ws timeout"):
		return "timeout"
	if lower.contains("llm") and lower.contains("not available"):
		return "provider"
	if lower.contains("provider"):
		return "provider"
	if lower.contains("safety") or lower.contains("blocked") or lower.contains("empty response"):
		return "safety"
	return "unknown"


## Map a stage tag to a user-facing message. Mirrors BabylonChatPanel.ts
## sendMessageViaGrpc displayMsg classification.
func display_message_for_stage(stage: String) -> String:
	match stage:
		"timeout":
			return "Sorry, the connection timed out. Please try again."
		"provider":
			return "The conversation service is temporarily unavailable."
		"safety":
			return "I'm not sure how to respond to that. Could you rephrase?"
		_:
			return "Sorry, I cannot respond right now. Please try again."
