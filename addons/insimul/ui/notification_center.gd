class_name InsimulNotificationCenter
extends Control
## Notification-center Control — a thin view over InsimulNotifications (US-GU1).
##
## notify(text, kind) enqueues a toast; _process ages them out via the model and
## repaints only when the visible set changes. Toasts stack top-right, colored by
## kind from the shared tokens. Paired with the loading screen as the US-GU1
## "pattern-proof pair": model holds the logic, this Control is the skin.

var _model := InsimulNotifications.new()
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = InsimulUiTokens.build_theme()
	_list = VBoxContainer.new()
	_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	_list.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	add_child(_list)
	_rebuild()


func _process(delta: float) -> void:
	if _model.tick(delta):
		_rebuild()


## Enqueue a toast. `kind` is an InsimulNotifications.Kind value.
func notify_toast(text: String, kind: int = InsimulNotifications.Kind.INFO) -> int:
	var id := _model.push(text, kind)
	_rebuild()
	return id


func model() -> InsimulNotifications:
	return _model


func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for item in _model.visible():
		_list.add_child(_make_toast(item))


func _make_toast(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := InsimulUiTokens._flat(
		InsimulUiTokens.color("surface"),
		InsimulUiTokens.color(String(item.get("color", "accent"))),
		int(InsimulUiTokens.RADIUS["md"]),
		int(InsimulUiTokens.SPACING["sm"])
	)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = String(item.get("text", ""))
	label.add_theme_color_override("font_color", InsimulUiTokens.color("text_primary"))
	panel.add_child(label)
	return panel
