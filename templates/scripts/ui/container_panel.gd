extends CanvasLayer
## Container Panel — displays loot when opening chests, barrels, and crates.
## Shows container contents in a grid with Take / Take All buttons.
## Integrates with InventorySystem and EventBus.

signal container_closed
signal item_taken(item_id: String)

const RARITY_COLORS := {
	"common":    Color(0.6, 0.6, 0.6),
	"uncommon":  Color(0.3, 0.8, 0.3),
	"rare":      Color(0.3, 0.5, 0.9),
	"epic":      Color(0.6, 0.3, 0.8),
	"legendary": Color(1.0, 0.8, 0.2),
}

const CONTAINER_LABELS := {
	"chest":  "Treasure Chest",
	"barrel": "Barrel",
	"crate":  "Crate",
}

var _is_open := false
var _container_id := ""
var _container_type := ""
var _items: Array = []

var _panel: PanelContainer = null
var _title_label: Label = null
var _item_grid: GridContainer = null
var _detail_label: RichTextLabel = null
var _take_button: Button = null
var _take_all_button: Button = null
var _close_button: Button = null
var _selected_index := -1

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false

func open_container(container_id: String, container_type: String, items: Array) -> void:
	_container_id = container_id
	_container_type = container_type
	_items = items.duplicate(true)
	_selected_index = -1
	_is_open = true
	visible = true
	_refresh()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	EventBus.emit_event({
		"type": "container_opened",
		"container_id": container_id,
		"container_type": container_type,
		"item_count": items.size(),
	})

func close_container() -> void:
	_is_open = false
	visible = false
	_container_id = ""
	_items.clear()
	container_closed.emit()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("menu"):
		close_container()
		get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.anchor_top = 0.15
	_panel.anchor_bottom = 0.85
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.10, 0.95)
	style.border_color = Color(0.55, 0.45, 0.30)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	title_bar.add_child(_title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer)
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.pressed.connect(close_container)
	title_bar.add_child(_close_button)

	# Item grid (5 columns)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_item_grid = GridContainer.new()
	_item_grid.columns = 5
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_grid)

	# Detail panel
	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.custom_minimum_size.y = 60
	_detail_label.add_theme_color_override("default_color", Color(0.85, 0.82, 0.75))
	vbox.add_child(_detail_label)

	# Action buttons
	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_bar)
	_take_button = Button.new()
	_take_button.text = "Take"
	_take_button.pressed.connect(_on_take)
	_take_button.disabled = true
	btn_bar.add_child(_take_button)
	_take_all_button = Button.new()
	_take_all_button.text = "Take All"
	_take_all_button.pressed.connect(_on_take_all)
	btn_bar.add_child(_take_all_button)

# ─────────────────────────────────────────────
# Refresh
# ─────────────────────────────────────────────

func _refresh() -> void:
	_title_label.text = CONTAINER_LABELS.get(_container_type, "Container")

	# Clear grid
	for child in _item_grid.get_children():
		child.queue_free()

	# Populate items
	for i in range(_items.size()):
		var item: Dictionary = _items[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(90, 90)
		var item_name: String = item.get("name", "?")
		var qty: int = item.get("quantity", 1)
		var rarity: String = item.get("rarity", "common")
		btn.text = "%s\nx%d" % [item_name, qty]

		# Rarity border
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.18, 0.16, 0.14)
		btn_style.border_color = RARITY_COLORS.get(rarity, Color(0.4, 0.4, 0.4))
		btn_style.set_border_width_all(2)
		btn_style.set_corner_radius_all(4)
		btn_style.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := btn_style.duplicate()
		hover_style.bg_color = Color(0.25, 0.22, 0.18)
		btn.add_theme_stylebox_override("hover", hover_style)

		var idx := i  # capture for closure
		btn.pressed.connect(func(): _select_item(idx))
		_item_grid.add_child(btn)

	if _items.is_empty():
		_detail_label.text = "[i]This container is empty.[/i]"
		_take_all_button.disabled = true
	else:
		_detail_label.text = "Select an item to inspect it."
		_take_all_button.disabled = false

	_take_button.disabled = true
	_selected_index = -1

func _select_item(index: int) -> void:
	_selected_index = index
	if index < 0 or index >= _items.size():
		_detail_label.text = ""
		_take_button.disabled = true
		return

	var item: Dictionary = _items[index]
	var rarity: String = item.get("rarity", "common")
	var color: Color = RARITY_COLORS.get(rarity, Color.WHITE)
	var color_hex := "#%s" % color.to_html(false)
	var desc: String = item.get("description", "")
	var item_type: String = item.get("type", item.get("itemType", ""))
	_detail_label.text = "[b][color=%s]%s[/color][/b] [i](%s)[/i]\n%s\nQuantity: %d" % [
		color_hex, item.get("name", "?"), item_type, desc, item.get("quantity", 1)
	]
	_take_button.disabled = false

# ─────────────────────────────────────────────
# Take actions
# ─────────────────────────────────────────────

func _on_take() -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var item: Dictionary = _items[_selected_index]
	_give_item_to_player(item)
	_items.remove_at(_selected_index)
	_refresh()

func _on_take_all() -> void:
	for item in _items:
		_give_item_to_player(item)
	_items.clear()
	_refresh()

func _give_item_to_player(item: Dictionary) -> void:
	InventorySystem.add_item(item)
	item_taken.emit(item.get("id", ""))
	EventBus.emit_event({
		"type": "item_collected",
		"item_id": item.get("id", ""),
		"item_name": item.get("name", ""),
		"quantity": item.get("quantity", 1),
		"source": "container",
	})
	# Play pickup sound if available
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("pickup")
