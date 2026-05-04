extends Control
## Main menu scene — entry point for the game.
## Provides New Game, Settings, and Quit buttons.

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var new_game_button: Button = $VBoxContainer/ButtonContainer/NewGameButton
@onready var settings_button: Button = $VBoxContainer/ButtonContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/ButtonContainer/QuitButton
@onready var settings_panel: PanelContainer = $SettingsPanel if has_node("SettingsPanel") else null

func _ready() -> void:
	title_label.text = "{{GAME_TITLE}}"
	new_game_button.pressed.connect(_on_new_game)
	settings_button.pressed.connect(_on_settings)
	quit_button.pressed.connect(_on_quit)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_settings() -> void:
	if settings_panel:
		settings_panel.visible = not settings_panel.visible

func _on_quit() -> void:
	get_tree().quit()
