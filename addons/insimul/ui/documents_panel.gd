class_name InsimulDocumentsPanel
extends Control
## Document reader Control — books, scrolls and letters (US-GU2).
##
## Paginates a document's text and pages through it. UNGATED on purpose: readable
## content is core world content rather than a band-111 module's IR section, so an
## educational or language-learning world (which activates no modules at all) still
## gets its reader. See panels.json.
##
## [method paginate] is a pure function and is where the only real behaviour lives:
## it breaks on paragraph boundaries so a page never splits a sentence when it does
## not have to.

signal document_opened(document_id: String)
signal document_closed(document_id: String)

const CHARS_PER_PAGE := 900

var _document_id := ""
var _pages: PackedStringArray = PackedStringArray()
var _page := 0
var _title: Label = null
var _body: RichTextLabel = null
var _page_label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	visible = false


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_title)

	_body = RichTextLabel.new()
	_body.custom_minimum_size = Vector2(480, 320)
	box.add_child(_body)

	var controls := HBoxContainer.new()
	var prev := Button.new()
	prev.text = "Previous"
	prev.pressed.connect(previous_page)
	controls.add_child(prev)
	_page_label = Label.new()
	_page_label.add_theme_color_override("font_color", InsimulUiTokens.color("text_secondary"))
	controls.add_child(_page_label)
	var next := Button.new()
	next.text = "Next"
	next.pressed.connect(next_page)
	controls.add_child(next)
	box.add_child(controls)


## Break `text` into pages of at most `limit` characters, preferring paragraph
## boundaries. Always answers at least one page, so a caller never has to special-
## case an empty document.
static func paginate(text: String, limit: int = CHARS_PER_PAGE) -> PackedStringArray:
	var pages := PackedStringArray()
	var cap := limit if limit > 0 else CHARS_PER_PAGE
	var current := ""
	for paragraph in text.split("\n\n"):
		var block := String(paragraph).strip_edges()
		if block.is_empty():
			continue
		if current.is_empty():
			current = block
		elif current.length() + 2 + block.length() <= cap:
			current += "\n\n" + block
		else:
			pages.append(current)
			current = block
		# A single paragraph longer than a page is split on the character count —
		# there is no boundary left to prefer.
		while current.length() > cap:
			pages.append(current.substr(0, cap))
			current = current.substr(cap)
	if not current.is_empty():
		pages.append(current)
	if pages.is_empty():
		pages.append("")
	return pages


## Open a document. `title` is presentation; `id` is what the signals carry.
func open_document(id: String, title: String, text: String) -> void:
	_document_id = id
	_pages = paginate(text)
	_page = 0
	if _title != null:
		_title.text = title
	visible = true
	_refresh()
	document_opened.emit(id)


func close() -> void:
	visible = false
	var closed := _document_id
	_document_id = ""
	if not closed.is_empty():
		document_closed.emit(closed)


func document_id() -> String:
	return _document_id


func page_count() -> int:
	return _pages.size()


func current_page() -> int:
	return _page


func page_text(index: int) -> String:
	if index < 0 or index >= _pages.size():
		return ""
	return _pages[index]


## Turn forward. Returns false at the last page — the reader stops, it does not wrap.
func next_page() -> bool:
	if _page + 1 >= _pages.size():
		return false
	_page += 1
	_refresh()
	return true


func previous_page() -> bool:
	if _page <= 0:
		return false
	_page -= 1
	_refresh()
	return true


func _refresh() -> void:
	if _body == null:
		return
	_body.text = page_text(_page)
	_page_label.text = "%d / %d" % [_page + 1, max(_pages.size(), 1)]
