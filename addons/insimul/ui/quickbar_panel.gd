class_name InsimulQuickbarPanel
extends Control
## Action quick-bar Control — the HUD hotbar (US-GU2).
##
## A fixed row of slots bound to action ids, triggered by click or by the number
## keys. Module-gated on `agentAi`, whose IR section (`systems.actions`) IS the
## action set a slot can hold: a world that activates no agent AI has nothing to
## bind, so the panel does not resolve.
##
## The panel does not EXECUTE an action — it emits [signal action_triggered] and
## the host runs it. That keeps the quick bar free of any engine dependency.

signal action_triggered(slot: int, action_id: String)

const SLOT_COUNT := 9

var _slots: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _row: HBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	theme = InsimulUiTokens.build_theme()
	_ensure_slots()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["xs"]))
	add_child(_row)
	for i in range(SLOT_COUNT):
		var button := Button.new()
		button.custom_minimum_size = Vector2(48, 48)
		button.pressed.connect(trigger_slot.bind(i))
		_row.add_child(button)
		_buttons.append(button)


## The slot array exists before _ready so the bar answers about its slots whether
## or not it is in a tree — the bindings are data, the buttons are the view.
func _ensure_slots() -> void:
	if _slots.size() == SLOT_COUNT:
		return
	_slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_slots[i] = {}


## Bind an action to a slot (0-based). An empty `action_id` clears it.
func assign_slot(slot: int, action_id: String, action_name: String = "") -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	_ensure_slots()
	if action_id.is_empty():
		_slots[slot] = {}
	else:
		_slots[slot] = {"id": action_id, "name": action_name if not action_name.is_empty() else action_id}
	_refresh()
	return true


## Fill the bar from an ordered action list ({ id, name? }), truncated to the bar.
func set_actions(actions: Array) -> void:
	for i in range(SLOT_COUNT):
		if i < actions.size():
			var entry: Dictionary = actions[i]
			assign_slot(i, String(entry.get("id", "")), String(entry.get("name", "")))
		else:
			assign_slot(i, "")


func slot(index: int) -> Dictionary:
	if index < 0 or index >= SLOT_COUNT:
		return {}
	_ensure_slots()
	return _slots[index].duplicate(true)


## Fire the action in `slot`. Returns false for an out-of-range or empty slot —
## an empty slot is not an error, it is a slot nobody bound.
func trigger_slot(index: int) -> bool:
	var entry := slot(index)
	if entry.is_empty():
		return false
	action_triggered.emit(index, String(entry.get("id", "")))
	return true


func _refresh() -> void:
	for i in range(_buttons.size()):
		var entry := slot(i)
		_buttons[i].text = String(entry.get("name", "")) if not entry.is_empty() else "%d" % (i + 1)
		_buttons[i].disabled = entry.is_empty()
