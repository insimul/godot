extends PanelContainer
## Inventory UI — full-screen inventory with grid, category tabs, detail panel,
## equipment slots, stats sidebar, and action buttons.
## Toggle with Tab key; pauses game while open.

signal inventory_closed

enum FilterCategory { ALL, WEAPONS_ARMOR, CONSUMABLES, QUEST, MATERIALS }

var _current_filter: FilterCategory = FilterCategory.ALL
var _filtered_items: Array[Dictionary] = []
var _selected_index: int = -1
var _slot_buttons: Array[Button] = []
var _inventory_system: Node = null

# UI references built in _build_ui()
var _grid_container: GridContainer = null
var _scroll_container: ScrollContainer = null
var _detail_panel: PanelContainer = null
var _detail_name: Label = null
var _detail_description: RichTextLabel = null
var _detail_weight: Label = null
var _detail_effects: Label = null
var _use_button: Button = null
var _drop_button: Button = null
var _equip_button: Button = null
var _health_label: Label = null
var _energy_label: Label = null
var _gold_label: Label = null
var _carry_weight_label: Label = null
var _slots_label: Label = null
var _weapon_slot_label: Label = null
var _armor_slot_label: Label = null
var _accessory_slot_label: Label = null
var _tab_all: Button = null
var _tab_weapons: Button = null
var _tab_consumables: Button = null
var _tab_quest: Button = null
var _tab_materials: Button = null

func _ready() -> void:
	visible = false
	_build_ui()
	_inventory_system = get_node_or_null("/root/InventorySystem")
	if _inventory_system:
		_inventory_system.item_added.connect(_on_item_added)
		_inventory_system.item_removed.connect(_on_item_removed)
		_inventory_system.gold_changed.connect(_on_gold_changed)
		_inventory_system.item_equipped.connect(func(_i): _refresh())
		_inventory_system.item_unequipped.connect(func(_i): _refresh())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_inventory()
			get_viewport().set_input_as_handled()

func toggle_inventory() -> void:
	if visible:
		close_inventory()
	else:
		open_inventory()

func open_inventory() -> void:
	_refresh()
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_inventory() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	clear_selection()
	inventory_closed.emit()

func set_category_filter(category: FilterCategory) -> void:
	_current_filter = category
	clear_selection()
	_refresh()

func _get_filtered_items() -> Array[Dictionary]:
	if not _inventory_system:
		return []
	var all_items: Array[Dictionary] = _inventory_system.get_all_items()
	if _current_filter == FilterCategory.ALL:
		return all_items
	var result: Array[Dictionary] = []
	for item in all_items:
		var item_type: String = str(item.get("type", "collectible"))
		match _current_filter:
			FilterCategory.WEAPONS_ARMOR:
				if item_type in ["weapon", "armor"]:
					result.append(item)
			FilterCategory.CONSUMABLES:
				if item_type in ["consumable", "food", "drink"]:
					result.append(item)
			FilterCategory.QUEST:
				if item_type in ["quest", "key"]:
					result.append(item)
			FilterCategory.MATERIALS:
				if item_type in ["material", "tool"]:
					result.append(item)
	return result

# --- Selection ---

func select_item(filtered_index: int) -> void:
	if filtered_index < 0 or filtered_index >= _filtered_items.size():
		return
	_selected_index = filtered_index
	_update_selection_highlight()
	_update_detail_panel()

func clear_selection() -> void:
	_selected_index = -1
	_update_selection_highlight()
	_update_detail_panel()

func has_selection() -> bool:
	return _selected_index >= 0 and _selected_index < _filtered_items.size()

func _get_selected_item() -> Dictionary:
	if not has_selection():
		return {}
	return _filtered_items[_selected_index]

# --- Action buttons ---

func can_use_selected() -> bool:
	var item := _get_selected_item()
	if item.is_empty():
		return false
	var item_type: String = str(item.get("type", "collectible"))
	return item_type in ["consumable", "food", "drink", "quest", "key"]

func can_drop_selected() -> bool:
	var item := _get_selected_item()
	if item.is_empty():
		return false
	if str(item.get("type", "collectible")) == "quest":
		return false
	return not item.get("equipped", false)

func can_equip_selected() -> bool:
	var item := _get_selected_item()
	if item.is_empty():
		return false
	var item_type: String = str(item.get("type", "collectible"))
	return item_type in ["weapon", "armor", "tool"]

func use_selected_item() -> void:
	var item := _get_selected_item()
	if item.is_empty() or not _inventory_system:
		return
	_inventory_system.use_item(item.get("id", ""))

func drop_selected_item() -> void:
	var item := _get_selected_item()
	if item.is_empty() or not _inventory_system:
		return
	_inventory_system.drop_item(item.get("id", ""))

func equip_selected_item() -> void:
	var item := _get_selected_item()
	if item.is_empty() or not _inventory_system:
		return
	if item.get("equipped", false):
		var slot: String = item.get("equip_slot", "")
		if slot.is_empty():
			slot = _inventory_system._get_slot_for_type(str(item.get("type", "")))
		_inventory_system.unequip_slot(slot)
	else:
		_inventory_system.equip_item(item.get("id", ""))

# --- Stats ---

func get_total_carry_weight() -> float:
	if not _inventory_system:
		return 0.0
	var total := 0.0
	for item in _inventory_system.get_all_items():
		total += float(item.get("weight", 0)) * float(item.get("quantity", 1))
	return total

func get_gold() -> int:
	if not _inventory_system:
		return 0
	return _inventory_system.get_gold()

func get_used_slots() -> int:
	if not _inventory_system:
		return 0
	return _inventory_system.get_all_items().size()

func get_max_slots() -> int:
	if not _inventory_system:
		return 20
	return _inventory_system.max_slots

# --- Rarity ---

func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon": return Color(0.2, 0.8, 0.2)
		"rare": return Color(0.3, 0.5, 1.0)
		"epic": return Color(0.7, 0.3, 0.9)
		"legendary": return Color(1.0, 0.65, 0.0)
		_: return Color(0.8, 0.8, 0.8) # common

# --- Display name (language learning) ---

func get_display_name(item: Dictionary) -> String:
	if _inventory_system and _inventory_system.has_method("get_display_name"):
		return _inventory_system.get_display_name(item)
	return item.get("name", item.get("id", ""))

# --- Event handlers ---

func _on_item_added(_item: Dictionary) -> void:
	_refresh()

func _on_item_removed(item_id: String) -> void:
	if has_selection():
		var selected := _get_selected_item()
		if selected.get("id", "") == item_id:
			clear_selection()
	_refresh()

func _on_gold_changed(_new_gold: int) -> void:
	_update_stats()

# --- Refresh ---

func _refresh() -> void:
	_filtered_items = _get_filtered_items()
	_rebuild_grid()
	_update_stats()
	_update_equipment_display()
	_update_detail_panel()
	_update_tab_highlights()

func _rebuild_grid() -> void:
	if not _grid_container:
		return
	# Clear old slots
	for child in _grid_container.get_children():
		child.queue_free()
	_slot_buttons.clear()

	for i in range(_filtered_items.size()):
		var item: Dictionary = _filtered_items[i]
		var btn := Button.new()
		var display_name := get_display_name(item)
		var qty: int = item.get("quantity", 1)
		btn.text = "%s x%d" % [display_name, qty] if qty > 1 else display_name
		btn.custom_minimum_size = Vector2(80, 80)
		btn.tooltip_text = item.get("description", "")

		# Rarity border color
		var rarity: String = str(item.get("rarity", "common"))
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
		style.border_color = get_rarity_color(rarity)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", style)

		var idx := i
		btn.pressed.connect(func(): select_item(idx))
		_grid_container.add_child(btn)
		_slot_buttons.append(btn)

	_update_selection_highlight()

func _update_selection_highlight() -> void:
	for i in range(_slot_buttons.size()):
		var btn: Button = _slot_buttons[i]
		if i == _selected_index:
			var highlight = StyleBoxFlat.new()
			highlight.bg_color = Color(0.3, 0.3, 0.4, 0.9)
			highlight.border_color = Color.YELLOW
			highlight.set_border_width_all(3)
			highlight.set_corner_radius_all(4)
			highlight.set_content_margin_all(4)
			btn.add_theme_stylebox_override("normal", highlight)
		else:
			var item: Dictionary = _filtered_items[i] if i < _filtered_items.size() else {}
			var rarity: String = str(item.get("rarity", "common"))
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
			style.border_color = get_rarity_color(rarity)
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			style.set_content_margin_all(4)
			btn.add_theme_stylebox_override("normal", style)

func _update_detail_panel() -> void:
	if not _detail_panel:
		return
	var item := _get_selected_item()
	if item.is_empty():
		_detail_panel.visible = false
		_use_button.visible = false
		_drop_button.visible = false
		_equip_button.visible = false
		return

	_detail_panel.visible = true
	_detail_name.text = get_display_name(item)
	_detail_description.text = item.get("description", "No description.")
	_detail_weight.text = "Weight: %.1f" % float(item.get("weight", 0))

	# Effects
	var effects: Dictionary = item.get("effects", {})
	if effects.is_empty():
		_detail_effects.text = ""
	else:
		var parts: Array[String] = []
		for key in effects:
			parts.append("%s: %s" % [key, str(effects[key])])
		_detail_effects.text = "Effects: " + ", ".join(parts)

	# Action button visibility
	_use_button.visible = can_use_selected()
	_drop_button.visible = can_drop_selected()
	_equip_button.visible = can_equip_selected()
	if can_equip_selected():
		_equip_button.text = "Unequip" if item.get("equipped", false) else "Equip"

func _update_stats() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % get_gold()
	if _carry_weight_label:
		_carry_weight_label.text = "Weight: %.1f" % get_total_carry_weight()
	if _slots_label:
		_slots_label.text = "Slots: %d / %d" % [get_used_slots(), get_max_slots()]

	# Player stats from player node
	var player = get_tree().get_first_node_in_group("player") if get_tree() else null
	if player:
		if _health_label and player.get("health") != null:
			_health_label.text = "Health: %d" % ceili(player.health)
		if _energy_label and player.get("energy") != null:
			_energy_label.text = "Energy: %d" % ceili(player.energy)

func _update_equipment_display() -> void:
	if not _inventory_system:
		return
	var weapon: Dictionary = _inventory_system.get_equipped_item("weapon")
	var armor: Dictionary = _inventory_system.get_equipped_item("armor")
	var accessory: Dictionary = _inventory_system.get_equipped_item("accessory")
	if _weapon_slot_label:
		_weapon_slot_label.text = "Weapon: %s" % get_display_name(weapon) if not weapon.is_empty() else "Weapon: ---"
	if _armor_slot_label:
		_armor_slot_label.text = "Armor: %s" % get_display_name(armor) if not armor.is_empty() else "Armor: ---"
	if _accessory_slot_label:
		_accessory_slot_label.text = "Accessory: %s" % get_display_name(accessory) if not accessory.is_empty() else "Accessory: ---"

func _update_tab_highlights() -> void:
	var tabs: Array[Button] = [_tab_all, _tab_weapons, _tab_consumables, _tab_quest, _tab_materials]
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.3, 0.5, 0.8, 0.9)
	active_style.set_corner_radius_all(4)
	active_style.set_content_margin_all(4)
	var inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	inactive_style.set_corner_radius_all(4)
	inactive_style.set_content_margin_all(4)
	for i in range(tabs.size()):
		if tabs[i]:
			tabs[i].add_theme_stylebox_override("normal", active_style if i == _current_filter else inactive_style)

# --- Build UI programmatically ---

func _build_ui() -> void:
	custom_minimum_size = Vector2(800, 600)
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.05
	anchor_top = 0.05
	anchor_right = 0.95
	anchor_bottom = 0.95

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	bg_style.set_corner_radius_all(8)
	bg_style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", bg_style)

	var root_vbox = VBoxContainer.new()
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root_vbox)

	# --- Header ---
	var header_hbox = HBoxContainer.new()
	root_vbox.add_child(header_hbox)

	var title = Label.new()
	title.text = "Inventory"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(close_inventory)
	header_hbox.add_child(close_btn)

	# --- Category tabs ---
	var tab_hbox = HBoxContainer.new()
	root_vbox.add_child(tab_hbox)

	_tab_all = _create_tab("All", FilterCategory.ALL)
	tab_hbox.add_child(_tab_all)
	_tab_weapons = _create_tab("Weapons/Armor", FilterCategory.WEAPONS_ARMOR)
	tab_hbox.add_child(_tab_weapons)
	_tab_consumables = _create_tab("Consumables", FilterCategory.CONSUMABLES)
	tab_hbox.add_child(_tab_consumables)
	_tab_quest = _create_tab("Quest", FilterCategory.QUEST)
	tab_hbox.add_child(_tab_quest)
	_tab_materials = _create_tab("Materials", FilterCategory.MATERIALS)
	tab_hbox.add_child(_tab_materials)

	# --- Main content (grid + sidebar) ---
	var content_hbox = HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(content_hbox)

	# Grid scroll area
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_hbox.add_child(_scroll_container)

	_grid_container = GridContainer.new()
	_grid_container.columns = 5
	_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_grid_container)

	# Right sidebar
	var sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(220, 0)
	content_hbox.add_child(sidebar)

	# Detail panel
	_detail_panel = PanelContainer.new()
	_detail_panel.visible = false
	var detail_style = StyleBoxFlat.new()
	detail_style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	detail_style.set_corner_radius_all(6)
	detail_style.set_content_margin_all(8)
	_detail_panel.add_theme_stylebox_override("panel", detail_style)
	sidebar.add_child(_detail_panel)

	var detail_vbox = VBoxContainer.new()
	_detail_panel.add_child(detail_vbox)

	_detail_name = Label.new()
	_detail_name.text = ""
	detail_vbox.add_child(_detail_name)

	_detail_description = RichTextLabel.new()
	_detail_description.bbcode_enabled = true
	_detail_description.fit_content = true
	_detail_description.scroll_active = false
	_detail_description.custom_minimum_size = Vector2(0, 40)
	detail_vbox.add_child(_detail_description)

	_detail_weight = Label.new()
	detail_vbox.add_child(_detail_weight)

	_detail_effects = Label.new()
	detail_vbox.add_child(_detail_effects)

	# Action buttons
	var action_hbox = HBoxContainer.new()
	detail_vbox.add_child(action_hbox)

	_use_button = Button.new()
	_use_button.text = "Use"
	_use_button.visible = false
	_use_button.pressed.connect(use_selected_item)
	action_hbox.add_child(_use_button)

	_drop_button = Button.new()
	_drop_button.text = "Drop"
	_drop_button.visible = false
	_drop_button.pressed.connect(drop_selected_item)
	action_hbox.add_child(_drop_button)

	_equip_button = Button.new()
	_equip_button.text = "Equip"
	_equip_button.visible = false
	_equip_button.pressed.connect(equip_selected_item)
	action_hbox.add_child(_equip_button)

	# Stats section
	var stats_label = Label.new()
	stats_label.text = "--- Stats ---"
	sidebar.add_child(stats_label)

	_health_label = Label.new()
	_health_label.text = "Health: --"
	sidebar.add_child(_health_label)

	_energy_label = Label.new()
	_energy_label.text = "Energy: --"
	sidebar.add_child(_energy_label)

	_gold_label = Label.new()
	_gold_label.text = "Gold: 0"
	sidebar.add_child(_gold_label)

	_carry_weight_label = Label.new()
	_carry_weight_label.text = "Weight: 0.0"
	sidebar.add_child(_carry_weight_label)

	_slots_label = Label.new()
	_slots_label.text = "Slots: 0 / 20"
	sidebar.add_child(_slots_label)

	# Equipment section
	var equip_label = Label.new()
	equip_label.text = "--- Equipment ---"
	sidebar.add_child(equip_label)

	_weapon_slot_label = Label.new()
	_weapon_slot_label.text = "Weapon: ---"
	sidebar.add_child(_weapon_slot_label)

	_armor_slot_label = Label.new()
	_armor_slot_label.text = "Armor: ---"
	sidebar.add_child(_armor_slot_label)

	_accessory_slot_label = Label.new()
	_accessory_slot_label.text = "Accessory: ---"
	sidebar.add_child(_accessory_slot_label)

func _create_tab(label_text: String, category: FilterCategory) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(80, 30)
	btn.pressed.connect(func(): set_category_filter(category))
	return btn
