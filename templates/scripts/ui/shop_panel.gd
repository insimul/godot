extends CanvasLayer
## Shop Panel — split merchant/player inventory for buying and selling.
## Opened via DialogueSystem when interacting with a merchant NPC.

signal item_purchased(item_id: String, quantity: int, cost: int)
signal item_sold(item_id: String, quantity: int, revenue: int)
signal shop_closed

const RARITY_COLORS := {
	"common":    Color(0.6, 0.6, 0.6),
	"uncommon":  Color(0.3, 0.8, 0.3),
	"rare":      Color(0.3, 0.5, 0.9),
	"epic":      Color(0.6, 0.3, 0.8),
	"legendary": Color(1.0, 0.8, 0.2),
}

var _is_open := false
var _merchant_items: Array = []
var _merchant_name := "Merchant"
var _selected_merchant_item: Dictionary = {}
var _selected_player_item: Dictionary = {}
var _quantity := 1
var _panel: PanelContainer = null
var _merchant_grid: VBoxContainer = null
var _player_grid: VBoxContainer = null
var _detail_label: RichTextLabel = null
var _gold_label: Label = null
var _buy_button: Button = null
var _sell_button: Button = null
var _close_button: Button = null
var _quantity_label: Label = null

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false

func open_shop(merchant_name: String, items: Array) -> void:
	_merchant_name = merchant_name
	_merchant_items = items
	_selected_merchant_item = {}
	_selected_player_item = {}
	_quantity = 1
	_is_open = true
	visible = true
	_refresh()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true

func close_shop() -> void:
	_is_open = false
	visible = false
	shop_closed.emit()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("menu"):
		close_shop()
		get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.1
	_panel.anchor_right = 0.9
	_panel.anchor_top = 0.05
	_panel.anchor_bottom = 0.95
	add_child(_panel)

	var main_vbox := VBoxContainer.new()
	_panel.add_child(main_vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	main_vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 22)
	title_bar.add_child(title)
	title_bar.add_child(_make_spacer())
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 18)
	title_bar.add_child(_gold_label)
	title_bar.add_child(_make_spacer())
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.pressed.connect(close_shop)
	title_bar.add_child(_close_button)

	# Split content
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(split)

	# Merchant side
	var merchant_panel := VBoxContainer.new()
	merchant_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(merchant_panel)
	var merchant_title := Label.new()
	merchant_title.text = "Merchant Inventory"
	merchant_title.add_theme_font_size_override("font_size", 16)
	merchant_panel.add_child(merchant_title)
	var merchant_scroll := ScrollContainer.new()
	merchant_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	merchant_panel.add_child(merchant_scroll)
	_merchant_grid = VBoxContainer.new()
	_merchant_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	merchant_scroll.add_child(_merchant_grid)

	# Player side
	var player_panel := VBoxContainer.new()
	player_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(player_panel)
	var player_title := Label.new()
	player_title.text = "Your Inventory"
	player_title.add_theme_font_size_override("font_size", 16)
	player_panel.add_child(player_title)
	var player_scroll := ScrollContainer.new()
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_panel.add_child(player_scroll)
	_player_grid = VBoxContainer.new()
	_player_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_scroll.add_child(_player_grid)

	# Detail + action bar
	var action_bar := HBoxContainer.new()
	main_vbox.add_child(action_bar)
	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_label.custom_minimum_size.y = 60
	action_bar.add_child(_detail_label)

	# Quantity controls
	var qty_box := HBoxContainer.new()
	action_bar.add_child(qty_box)
	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.pressed.connect(func(): _quantity = maxi(1, _quantity - 1); _refresh_detail())
	qty_box.add_child(minus_btn)
	_quantity_label = Label.new()
	_quantity_label.text = "1"
	_quantity_label.custom_minimum_size.x = 30
	_quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_box.add_child(_quantity_label)
	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.pressed.connect(func(): _quantity += 1; _refresh_detail())
	qty_box.add_child(plus_btn)

	_buy_button = Button.new()
	_buy_button.text = "Buy"
	_buy_button.pressed.connect(_on_buy)
	action_bar.add_child(_buy_button)
	_sell_button = Button.new()
	_sell_button.text = "Sell"
	_sell_button.pressed.connect(_on_sell)
	action_bar.add_child(_sell_button)

# ─────────────────────────────────────────────
# Refresh display
# ─────────────────────────────────────────────

func _refresh() -> void:
	_gold_label.text = "Gold: %d" % InventorySystem.gold
	_refresh_merchant_list()
	_refresh_player_list()
	_refresh_detail()

func _refresh_merchant_list() -> void:
	for child in _merchant_grid.get_children():
		child.queue_free()
	for item in _merchant_items:
		var btn := Button.new()
		var item_name: String = item.get("name", "?")
		var price: int = item.get("value", 10)
		var rarity: String = item.get("rarity", "common")
		var color: Color = RARITY_COLORS.get(rarity, Color.WHITE)
		btn.text = "%s — %d gold" % [item_name, price]
		btn.add_theme_color_override("font_color", color)
		btn.pressed.connect(func(): _select_merchant_item(item))
		_merchant_grid.add_child(btn)

func _refresh_player_list() -> void:
	for child in _player_grid.get_children():
		child.queue_free()
	var items: Array = InventorySystem.get_all_items()
	for item in items:
		if item.get("type", "") == "quest":
			continue  # Can't sell quest items
		var btn := Button.new()
		var sell_value: int = item.get("sell_value", item.get("value", 5) / 2)
		var qty: int = item.get("quantity", 1)
		btn.text = "%s (x%d) — %d gold" % [item.get("name", "?"), qty, sell_value]
		btn.pressed.connect(func(): _select_player_item(item))
		_player_grid.add_child(btn)

func _refresh_detail() -> void:
	_quantity_label.text = str(_quantity)
	if not _selected_merchant_item.is_empty():
		var price: int = _selected_merchant_item.get("value", 10) * _quantity
		var desc: String = _selected_merchant_item.get("description", "")
		_detail_label.text = "[b]%s[/b]\n%s\nCost: %d gold" % [_selected_merchant_item.get("name", ""), desc, price]
		_buy_button.disabled = price > InventorySystem.gold
		_sell_button.disabled = true
	elif not _selected_player_item.is_empty():
		var sell_val: int = _selected_player_item.get("sell_value", _selected_player_item.get("value", 5) / 2) * _quantity
		_detail_label.text = "[b]%s[/b]\nSell for: %d gold" % [_selected_player_item.get("name", ""), sell_val]
		_buy_button.disabled = true
		_sell_button.disabled = false
	else:
		_detail_label.text = "Select an item to buy or sell."
		_buy_button.disabled = true
		_sell_button.disabled = true

func _select_merchant_item(item: Dictionary) -> void:
	_selected_merchant_item = item
	_selected_player_item = {}
	_quantity = 1
	_refresh_detail()

func _select_player_item(item: Dictionary) -> void:
	_selected_player_item = item
	_selected_merchant_item = {}
	_quantity = 1
	_refresh_detail()

# ─────────────────────────────────────────────
# Buy / Sell actions
# ─────────────────────────────────────────────

func _on_buy() -> void:
	if _selected_merchant_item.is_empty():
		return
	var price: int = _selected_merchant_item.get("value", 10) * _quantity
	if InventorySystem.gold < price:
		return
	InventorySystem.remove_gold(price)
	var buy_item := _selected_merchant_item.duplicate()
	buy_item["quantity"] = _quantity
	InventorySystem.add_item(buy_item)
	item_purchased.emit(_selected_merchant_item.get("id", ""), _quantity, price)
	EventBus.emit_event({
		"type": "item_purchased",
		"item_id": _selected_merchant_item.get("id", ""),
		"item_name": _selected_merchant_item.get("name", ""),
		"quantity": _quantity,
		"cost": price,
	})
	_refresh()

func _on_sell() -> void:
	if _selected_player_item.is_empty():
		return
	var sell_val: int = _selected_player_item.get("sell_value", _selected_player_item.get("value", 5) / 2) * _quantity
	var item_id: String = _selected_player_item.get("id", "")
	if InventorySystem.remove_item(item_id, _quantity):
		InventorySystem.add_gold(sell_val)
		item_sold.emit(item_id, _quantity, sell_val)
		_selected_player_item = {}
		_refresh()

func _make_spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s
