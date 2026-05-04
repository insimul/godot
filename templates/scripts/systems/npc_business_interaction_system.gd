extends Node
## NPC Business Interaction System — shops and services.
## Matches shared/game-engine/rendering/NPCBusinessInteractionSystem.ts, BabylonShopPanel.ts.

signal shop_opened(business_id: String)
signal item_purchased(item_id: String, price: int)
signal item_sold(item_id: String, price: int)

const BUSINESS_INVENTORIES := {
	"blacksmith": [
		{"id": "iron_sword", "name": "Iron Sword", "price": 50, "category": "weapon"},
		{"id": "iron_shield", "name": "Iron Shield", "price": 40, "category": "armor"},
		{"id": "iron_helmet", "name": "Iron Helmet", "price": 30, "category": "armor"},
	],
	"tavern": [
		{"id": "ale", "name": "Ale", "price": 5, "category": "consumable"},
		{"id": "bread", "name": "Bread", "price": 3, "category": "consumable"},
		{"id": "stew", "name": "Hearty Stew", "price": 8, "category": "consumable"},
	],
	"market": [
		{"id": "apple", "name": "Apple", "price": 2, "category": "consumable"},
		{"id": "rope", "name": "Rope", "price": 10, "category": "material"},
		{"id": "torch", "name": "Torch", "price": 5, "category": "tool"},
		{"id": "potion_health", "name": "Health Potion", "price": 25, "category": "consumable"},
	],
	"general_store": [
		{"id": "bandage", "name": "Bandage", "price": 8, "category": "consumable"},
		{"id": "lantern", "name": "Lantern", "price": 15, "category": "tool"},
		{"id": "backpack", "name": "Backpack", "price": 20, "category": "tool"},
		{"id": "map_local", "name": "Local Map", "price": 12, "category": "tool"},
	],
}

var _shop_panel: CanvasLayer = null
var _grid: GridContainer = null
var _gold_label: Label = null
var _current_business_id := ""
var _current_items: Array = []

func _ready() -> void:
	_build_shop_ui()

func open_shop(business_id: String, business_type: String) -> void:
	_current_business_id = business_id
	_current_items = BUSINESS_INVENTORIES.get(business_type, BUSINESS_INVENTORIES["general_store"])
	_populate_grid()
	_shop_panel.visible = true
	_update_gold_display()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	shop_opened.emit(business_id)

func close_shop() -> void:
	_shop_panel.visible = false
	_current_business_id = ""
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _build_shop_ui() -> void:
	_shop_panel = CanvasLayer.new()
	_shop_panel.layer = 15
	_shop_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_shop_panel.visible = false
	add_child(_shop_panel)

	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.15
	panel.anchor_top = 0.1
	panel.anchor_right = 0.85
	panel.anchor_bottom = 0.9
	_shop_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Shop"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_gold_label = Label.new()
	_gold_label.text = "Gold: 0"
	header.add_child(_gold_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close_shop)
	header.add_child(close_btn)

	# Item grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

func _populate_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()

	for item in _current_items:
		var btn := Button.new()
		btn.text = "%s\n%d gold" % [item.get("name", ""), item.get("price", 0)]
		btn.custom_minimum_size = Vector2(120, 80)
		btn.pressed.connect(func(): _buy_item(item))
		_grid.add_child(btn)

func _buy_item(item: Dictionary) -> void:
	var price: int = item.get("price", 0)
	if InventorySystem.gold < price:
		print("[Shop] Not enough gold")
		return
	InventorySystem.set_gold(InventorySystem.gold - price)
	InventorySystem.add_item(item)
	_update_gold_display()
	item_purchased.emit(item.get("id", ""), price)

func _update_gold_display() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % InventorySystem.gold
