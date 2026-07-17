@tool
extends EditorPlugin
## Insimul editor plugin — registers the runtime autoload, the Binding Editor dock
## (US-GB3), and the editor backend-connection docks: World Browser + Generation
## Console (US-GE2), both over a shared InsimulEditorSession (US-GE1).

const BindingDock := preload("res://addons/insimul/editor/dock/insimul_binding_dock.gd")
const WorldBrowserDock := preload("res://addons/insimul/editor/browser/insimul_world_browser_dock.gd")
const GenerationConsoleDock := preload("res://addons/insimul/editor/generation/insimul_generation_console_dock.gd")

var _binding_dock: Control
var _browser_dock: Control
var _generation_dock: Control
var _session: InsimulEditorSession


func _enter_tree() -> void:
	add_autoload_singleton("InsimulClient", "res://addons/insimul/insimul_client.gd")

	# The editor's own session (separate from the runtime autoload). Backed by the
	# real HTTPRequest transport (this plugin Node hosts the request children) and
	# loaded from ProjectSettings (URL) + EditorSettings (token).
	_session = InsimulEditorSession.new(InsimulV1HttpTransport.new(self))
	_session.load_settings()

	# Binding Editor dock — taxonomy tree, bound/unbound status, scene picker,
	# bind-descendants, suggestions, pack import/export (US-GB3).
	_binding_dock = BindingDock.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _binding_dock)

	# World Browser dock — worlds list/detail/stats, compatibility badge,
	# Import/Sync with dry-run, open-in-web (US-GE2).
	_browser_dock = WorldBrowserDock.new(_session)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _browser_dock)

	# Generation Console dock — run generators as jobs, SSE progress + polling
	# fallback, sync-now (US-GE2).
	_generation_dock = GenerationConsoleDock.new(_session)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BR, _generation_dock)


func _exit_tree() -> void:
	for dock in [_binding_dock, _browser_dock, _generation_dock]:
		if dock != null:
			remove_control_from_docks(dock)
			dock.queue_free()
	_binding_dock = null
	_browser_dock = null
	_generation_dock = null
	_session = null

	remove_autoload_singleton("InsimulClient")
