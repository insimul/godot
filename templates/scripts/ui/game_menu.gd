extends CanvasLayer
## Game menu (Esc to toggle).
## Mirrors BabylonGame's GameMenuSystem with tabs for Character, Journal,
## Quests, Inventory, Crafting, Map, Photos, Vocabulary, Skills, Notices,
## Contacts, Notifications, and System.

signal menu_opened
signal menu_closed
signal save_requested(slot_index: int)
signal load_requested(slot_index: int)

## Available menu tabs matching GameMenuSystem.ts MenuTab type.
enum MenuTab {
	CHARACTER, REST, JOURNAL, CLUES, QUESTS, INVENTORY, CRAFTING,
	MAP, PHOTOS, VOCABULARY, SKILLS, NOTICES, CONTACTS, NOTIFICATIONS, SYSTEM
}

@onready var menu_panel: Control = $MenuPanel if has_node("MenuPanel") else null

var _is_open := false
var _active_tab: int = MenuTab.SYSTEM
var _target_language := ""

## Guild quest progress data — set via set_guild_quest_data()
var _guild_quest_data: Array[Dictionary] = []
## Narrative history entries for Story So Far — set via set_narrative_history()
var _narrative_history: Array[Dictionary] = []
## Clue chapter groups for chapter-organized clue rendering — set via set_chapter_clue_groups()
## Each entry: { chapterId, chapterTitle, chapterNumber, clueIds }
var _chapter_clue_groups: Array[Dictionary] = []
## Save slot data — each entry: { slotIndex, savedAt, gameTime, zoneName, playerGold, playerHealth, playerEnergy, inventoryCount, questCount, playerLevel }
var _save_slots: Array[Dictionary] = []

## Player data for character sheet tab
var _player_data: Dictionary = {}
## Quest data for quest journal tab
var _quest_data: Array[Dictionary] = []
## Inventory data for inventory tab
var _inventory_data: Array[Dictionary] = []
## Contact data for contacts tab
var _contact_data: Array[Dictionary] = []
## Map data for map tab
var _map_data: Dictionary = {}
## World data for world info display
var _world_data: Dictionary = {}
## Reputation data for character sheet
var _reputation_data: Array[Dictionary] = []
## Rule data for rules/library tab
var _rule_data: Array[Dictionary] = []

## Graphics settings
var _graphics_quality := 3.0
var _render_distance := 200.0
var _fullscreen := true

## Accessibility settings
var _subtitles_enabled := true
var _colorblind_mode := false
var _ui_scale := 1.0
var _text_size := 1.0

func _ready() -> void:
	if menu_panel:
		menu_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		toggle_menu()
	# Quick save/load hotkeys
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			quick_save()
		elif event.keycode == KEY_F9:
			quick_load()

func toggle_menu() -> void:
	_is_open = not _is_open
	if menu_panel:
		menu_panel.visible = _is_open
	get_tree().paused = _is_open
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _is_open else Input.MOUSE_MODE_CAPTURED)
	if _is_open:
		menu_opened.emit()
	else:
		menu_closed.emit()

## Open the menu to a specific tab.
func open(tab: int = MenuTab.SYSTEM) -> void:
	_active_tab = tab
	if not _is_open:
		toggle_menu()

## Close the menu.
func close() -> void:
	if _is_open:
		toggle_menu()

func resume_game() -> void:
	toggle_menu()

## Set the target language for language-learning features.
func set_target_language(language: String) -> void:
	_target_language = language

## Update time display data.
func update_time(time_string: String, day: int, time_of_day: String) -> void:
	pass

## Quick-save the current game state to slot 0.
func quick_save() -> void:
	save_requested.emit(0)
	print("[GameMenu] Quick save requested (slot 0)")

## Quick-load the last saved game state from slot 0.
func quick_load() -> void:
	load_requested.emit(0)
	print("[GameMenu] Quick load requested (slot 0)")

## Save to a specific slot index.
func save_to_slot(slot_index: int) -> void:
	save_requested.emit(slot_index)
	print("[GameMenu] Save to slot %d" % slot_index)

## Load from a specific slot index.
func load_from_slot(slot_index: int) -> void:
	load_requested.emit(slot_index)
	print("[GameMenu] Load from slot %d" % slot_index)

## Set save slot data for the save/load panel.
## Each entry: { slotIndex, savedAt, gameTime, zoneName, playerGold, playerHealth, playerEnergy, inventoryCount, questCount, playerLevel }
func set_save_slots(slots: Array[Dictionary]) -> void:
	_save_slots = slots

## Set player data for the character sheet tab.
func set_player_data(data: Dictionary) -> void:
	_player_data = data

## Set quest data for the quest journal tab.
func set_quest_data(quests: Array[Dictionary]) -> void:
	_quest_data = quests

## Set inventory data for the inventory tab.
func set_inventory_data(items: Array[Dictionary]) -> void:
	_inventory_data = items

## Set contact data for the contacts tab.
func set_contact_data(contacts: Array[Dictionary]) -> void:
	_contact_data = contacts

## Set map data for the map tab.
func set_map_data(data: Dictionary) -> void:
	_map_data = data

## Set world data for world info display.
func set_world_data(data: Dictionary) -> void:
	_world_data = data

## Set reputation data for the character sheet.
func set_reputation_data(data: Array[Dictionary]) -> void:
	_reputation_data = data

## Set rule data for the rules/library tab.
func set_rule_data(rules: Array[Dictionary]) -> void:
	_rule_data = rules

## Set graphics quality level (0-5).
func set_graphics_quality(level: float) -> void:
	_graphics_quality = level

## Set render distance.
func set_render_distance(distance: float) -> void:
	_render_distance = distance

## Set fullscreen mode.
func set_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

## Set subtitles enabled state.
func set_subtitles_enabled(enabled: bool) -> void:
	_subtitles_enabled = enabled

## Set colorblind mode.
func set_colorblind_mode(enabled: bool) -> void:
	_colorblind_mode = enabled

## Set UI scale factor.
func set_ui_scale(scale: float) -> void:
	_ui_scale = scale

## Set text size multiplier.
func set_text_size(size: float) -> void:
	_text_size = size

## Open a specific tab panel. Stub for tabs that will be fully implemented
## in extended GDScript or scene files (character sheet, journal, crafting,
## vocabulary, skill tree, contacts, notifications).
func open_tab(tab: int) -> void:
	_active_tab = tab
	if not _is_open:
		toggle_menu()
	print("[GameMenu] Opening tab: %d" % tab)

## Set narrative history entries for the Story So Far section.
## Each entry: { chapterId, chapterNumber, title, introNarrative, outroNarrative, mysteryDetails }
func set_narrative_history(history: Array[Dictionary]) -> void:
	_narrative_history = history

## Set guild quest progress data.
## Each entry: { guildId, guildTier, status }
func set_guild_quest_data(data: Array[Dictionary]) -> void:
	_guild_quest_data = data

## Set chapter clue groups for chapter-organized clue rendering in the journal.
## Each entry: { chapterId, chapterTitle, chapterNumber, clueIds }
func set_chapter_clue_groups(groups: Array[Dictionary]) -> void:
	_chapter_clue_groups = groups

func show_journal() -> void:
	# Journal/Story So Far — placeholder for full journal UI
	# In the Babylon.js source, this opens tabs for:
	# Character, Quest Journal (with Story So Far), Clues, Inventory,
	# Vocabulary, Notices/Library, Guild Skill Trees, and System.
	print("[GameMenu] Journal: %d narrative entries, %d guild quests" % [_narrative_history.size(), _guild_quest_data.size()])
	_active_tab = MenuTab.JOURNAL

func quit_game() -> void:
	get_tree().quit()
