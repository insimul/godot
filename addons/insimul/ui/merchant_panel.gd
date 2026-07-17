class_name InsimulMerchantPanel
extends Control
## Merchant Control — a thin view over InsimulTradeModel (US-GU2).
##
## Split buy/sell over a merchant's stock + the player's inventory. Buy moves gold
## player->merchant and item merchant->player; sell is the reverse. Everything runs
## THROUGH the trade model against save.currentState (player + npcs.merchantStates),
## so gold and items are conserved and there is no private store (the state-location
## invariant). Affordability / stock checks are the model's. Shared matrices:
## trade-cases.json.

signal item_bought(item_id: String, qty: int)
signal item_sold(item_id: String, qty: int)

var _model := InsimulTradeModel.new()
var _merchant_id := ""
var _gold_label: Label = null
var _merchant_list: VBoxContainer = null
var _player_list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	visible = false


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	add_child(box)

	_gold_label = Label.new()
	box.add_child(_gold_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["lg"]))
	_merchant_list = VBoxContainer.new()
	_player_list = VBoxContainer.new()
	columns.add_child(_merchant_list)
	columns.add_child(_player_list)
	box.add_child(columns)


## Open a merchant backed by the live save.currentState.
func open(current_state: Dictionary, merchant_id: String) -> void:
	_model.attach(current_state)
	_merchant_id = merchant_id
	visible = true
	_refresh()


func model() -> InsimulTradeModel:
	return _model


func buy(item_id: String, qty: int = 1) -> bool:
	var r := _model.buy(_merchant_id, item_id, qty)
	if r.get("ok", false):
		item_bought.emit(item_id, qty)
		_refresh()
	return r.get("ok", false)


func sell(item_id: String, qty: int = 1) -> bool:
	var r := _model.sell(_merchant_id, item_id, qty)
	if r.get("ok", false):
		item_sold.emit(item_id, qty)
		_refresh()
	return r.get("ok", false)


func _refresh() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Gold: %d      Merchant: %d" % [_model.player_gold(), _model.merchant_gold(_merchant_id)]
	_fill(_merchant_list, _model.merchant_items(_merchant_id), buy)
	_fill(_player_list, _model.player_items(), sell)


func _fill(list: VBoxContainer, items: Array, action: Callable) -> void:
	for child in list.get_children():
		child.queue_free()
	for item in items:
		var row := Button.new()
		var item_id := String(item.get("itemId", "?"))
		row.text = "%s ×%d (%d)" % [item_id, int(item.get("quantity", 0)), int(item.get("value", 0))]
		row.pressed.connect(action.bind(item_id, 1))
		list.add_child(row)
