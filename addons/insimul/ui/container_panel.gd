class_name InsimulContainerPanel
extends Control
## Container loot Control — a thin view over InsimulTradeModel (US-GU2).
##
## Shows a container's contents (chest / barrel / crate) with Take / Take All. Every
## transfer moves items from containers.containers[id] into player.inventory THROUGH
## the trade model, so both sides live in save.currentState (the state-location
## invariant — items move, never duplicate). Shared matrices: trade-cases.json.

signal item_taken(item_id: String)
signal container_emptied

var _model := InsimulTradeModel.new()
var _container_id := ""
var _title: Label = null
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	visible = false


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_title)

	_list = VBoxContainer.new()
	box.add_child(_list)

	var take_all := Button.new()
	take_all.text = "Take All"
	take_all.pressed.connect(_on_take_all)
	box.add_child(take_all)


## Open a container backed by the live save.currentState.
func open(current_state: Dictionary, container_id: String, title: String = "Container") -> void:
	_model.attach(current_state)
	_container_id = container_id
	if _title != null:
		_title.text = title
	visible = true
	_refresh()


func model() -> InsimulTradeModel:
	return _model


func take(item_id: String, qty: int = 0) -> bool:
	var r := _model.take_from_container(_container_id, item_id, qty)
	if r.get("ok", false):
		item_taken.emit(item_id)
		_refresh()
	return r.get("ok", false)


func _on_take_all() -> void:
	_model.take_all_from_container(_container_id)
	container_emptied.emit()
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for item in _model.container_items(_container_id):
		var row := Button.new()
		var item_id := String(item.get("itemId", "?"))
		row.text = "%s ×%d" % [item_id, int(item.get("quantity", 0))]
		row.pressed.connect(take.bind(item_id, 0))
		_list.add_child(row)
