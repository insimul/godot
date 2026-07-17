class_name InsimulNotifications
extends RefCounted
## Transient-notification (toast) view-model (US-GU1).
##
## A pure, timing-driven queue: callers push() notifications with a kind
## (info/success/warning/danger, mapped to a token color) and an optional
## lifetime; tick(delta) ages them out. Kept UI-free so the notification_center
## Control (and the shared tests) drive the SAME logic. Paired with the loading
## screen as the US-GU1 "pattern-proof pair" — both are model + thin Control.

enum Kind { INFO, SUCCESS, WARNING, DANGER }

## Default seconds a notification stays visible before tick() expires it.
const DEFAULT_LIFETIME := 4.0

## Kind -> token color name (see InsimulUiTokens.COLORS).
const KIND_COLOR := {
	Kind.INFO: "accent",
	Kind.SUCCESS: "success",
	Kind.WARNING: "warning",
	Kind.DANGER: "danger",
}

var _items: Array = []
var _next_id: int = 1


## Enqueue a notification. Returns its id (so a caller can dismiss() it early).
func push(text: String, kind: int = Kind.INFO, lifetime: float = DEFAULT_LIFETIME) -> int:
	var id := _next_id
	_next_id += 1
	_items.append({
		"id": id,
		"text": text,
		"kind": kind,
		"remaining": lifetime,
		"color": String(KIND_COLOR.get(kind, "accent")),
	})
	return id


## Age every notification by `delta` seconds, dropping any that expired. Returns
## true if the visible set changed (so a Control knows to repaint).
func tick(delta: float) -> bool:
	if _items.is_empty():
		return false
	var before := _items.size()
	var kept: Array = []
	for item in _items:
		item["remaining"] = float(item["remaining"]) - delta
		if item["remaining"] > 0.0:
			kept.append(item)
	_items = kept
	return _items.size() != before


## Dismiss a notification by id early. Returns true if one was removed.
func dismiss(id: int) -> bool:
	for i in range(_items.size()):
		if int(_items[i]["id"]) == id:
			_items.remove_at(i)
			return true
	return false


## Currently visible notifications (oldest first), as duplicated dictionaries.
func visible() -> Array:
	return _items.duplicate(true)


func count() -> int:
	return _items.size()


func clear() -> void:
	_items.clear()
