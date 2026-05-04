extends CanvasLayer
## Document Reading Panel and Skill Tree — books, scrolls, skill trees, rules panel.
## Matches BabylonSkillTreePanel.ts, DocumentReadingPanel.ts, BabylonRulesPanel.ts.

signal document_closed
signal skill_unlocked(skill_id: String)

var _document_panel: PanelContainer = null
var _doc_text: RichTextLabel = null
var _doc_title: Label = null
var _page_label: Label = null
var _pages: Array[String] = []
var _current_page := 0

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_document_ui()
	visible = false

func open_document(title: String, content: String) -> void:
	# Split into pages
	_pages = _split_into_pages(content)
	_current_page = 0
	_doc_title.text = title
	_show_page()
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_document() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	document_closed.emit()

func _show_page() -> void:
	if _current_page < _pages.size():
		_doc_text.text = _pages[_current_page]
		_page_label.text = "Page %d / %d" % [_current_page + 1, _pages.size()]

func _split_into_pages(content: String) -> Array[String]:
	var pages: Array[String] = []
	var lines := content.split("\n")
	var page := ""
	var line_count := 0
	for line in lines:
		page += line + "\n"
		line_count += 1
		if line_count >= 20:
			pages.append(page)
			page = ""
			line_count = 0
	if page.strip_edges() != "":
		pages.append(page)
	if pages.is_empty():
		pages.append(content)
	return pages

func _build_document_ui() -> void:
	_document_panel = PanelContainer.new()
	_document_panel.anchors_preset = Control.PRESET_CENTER
	_document_panel.anchor_left = 0.15
	_document_panel.anchor_top = 0.05
	_document_panel.anchor_right = 0.85
	_document_panel.anchor_bottom = 0.95
	add_child(_document_panel)

	var vbox := VBoxContainer.new()
	_document_panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)
	_doc_title = Label.new()
	_doc_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_doc_title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close_document)
	header.add_child(close_btn)

	# Content
	_doc_text = RichTextLabel.new()
	_doc_text.bbcode_enabled = true
	_doc_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_doc_text.scroll_active = true
	vbox.add_child(_doc_text)

	# Navigation
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(nav)
	var prev_btn := Button.new()
	prev_btn.text = "< Prev"
	prev_btn.pressed.connect(func():
		_current_page = max(0, _current_page - 1)
		_show_page()
	)
	nav.add_child(prev_btn)
	_page_label = Label.new()
	_page_label.custom_minimum_size.x = 100
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_page_label)
	var next_btn := Button.new()
	next_btn.text = "Next >"
	next_btn.pressed.connect(func():
		_current_page = min(_pages.size() - 1, _current_page + 1)
		_show_page()
	)
	nav.add_child(next_btn)
