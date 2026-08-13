class_name InsimulNoticeBoardPanel
extends Control
## Notice-board Control — the settlement's posted notices (US-GU2).
##
## A list of notices ({ id, title, body, read? }) with a reading pane and an unread
## count. UNGATED on purpose: notices are core world content, not a band-111
## module's IR section, so a puzzle or language-learning world posts them too. See
## panels.json — the gate is data, and "gated by nothing" is a recorded answer
## rather than an omission.

signal notice_read(notice_id: String)
signal quest_requested(quest_id: String)

var _notices: Array = []
var _by_id: Dictionary = {}
var _selected := ""
var _list: VBoxContainer = null
var _title: Label = null
var _body: RichTextLabel = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	visible = false
	_refresh()


func _build_ui() -> void:
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["lg"]))
	add_child(columns)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["xs"]))
	columns.add_child(_list)

	var reader := VBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	reader.add_child(_title)
	_body = RichTextLabel.new()
	_body.custom_minimum_size = Vector2(360, 240)
	reader.add_child(_body)
	columns.add_child(reader)


## Post the board's notices. Unknown fields are preserved, so a notice may carry a
## `questId` the host turns into an offer.
func set_notices(notices: Array) -> void:
	_notices.clear()
	_by_id.clear()
	for n in notices:
		var id := String((n as Dictionary).get("id", ""))
		if id.is_empty():
			continue
		var entry: Dictionary = (n as Dictionary).duplicate(true)
		_notices.append(entry)
		_by_id[id] = entry
	_selected = ""
	_refresh()


func notices() -> Array:
	var out: Array = []
	for n in _notices:
		out.append((n as Dictionary).duplicate(true))
	return out


func unread_count() -> int:
	var count := 0
	for n in _notices:
		if not bool((n as Dictionary).get("read", false)):
			count += 1
	return count


func selected_id() -> String:
	return _selected


## Open a notice: shows it and marks it read (a board the player has read stops
## nagging). Returns false for an unknown id.
func select(id: String) -> bool:
	if not _by_id.has(id):
		return false
	_selected = id
	var was_read := bool(_by_id[id].get("read", false))
	_by_id[id]["read"] = true
	if not was_read:
		notice_read.emit(id)
	_refresh()
	return true


## Ask the host to offer the quest the selected notice advertises.
func request_quest() -> String:
	if _selected.is_empty():
		return ""
	var quest_id := String(_by_id[_selected].get("questId", ""))
	if not quest_id.is_empty():
		quest_requested.emit(quest_id)
	return quest_id


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for n in _notices:
		var row := Button.new()
		var id := String((n as Dictionary).get("id", ""))
		var mark := "" if bool((n as Dictionary).get("read", false)) else "• "
		row.text = "%s%s" % [mark, String((n as Dictionary).get("title", id))]
		row.pressed.connect(select.bind(id))
		_list.add_child(row)
	if _by_id.has(_selected):
		_title.text = String(_by_id[_selected].get("title", ""))
		_body.text = String(_by_id[_selected].get("body", ""))
	else:
		_title.text = "Notice board"
		_body.text = ""
