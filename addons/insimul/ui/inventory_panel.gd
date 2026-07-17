class_name InsimulInventoryPanel
extends Control
## Inventory Control — a thin view over InsimulTradeModel (US-GU2).
##
## Lists the player's carried items + gold, read straight off save.currentState via
## the trade model (no private store — the state-location invariant). Bind the live
## currentState with attach(); the panel never caches items, so it always reflects
## the save. Shared matrices: trade-cases.json.

var _model := InsimulTradeModel.new()
var _gold_label: Label = null
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	add_child(box)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["subtitle"]))
	box.add_child(_gold_label)

	_list = VBoxContainer.new()
	box.add_child(_list)


## Bind the live save.currentState slice (player / containers / npcs).
func attach(current_state: Dictionary) -> void:
	_model.attach(current_state)
	_refresh()


func model() -> InsimulTradeModel:
	return _model


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Gold: %d" % _model.player_gold()
	for child in _list.get_children():
		child.queue_free()
	for item in _model.player_items():
		var row := Label.new()
		row.text = "%s ×%d" % [String(item.get("itemId", "?")), int(item.get("quantity", 0))]
		_list.add_child(row)
