# -----------------------------------------------------------------------------
# GENERATED FILE — DO NOT EDIT BY HAND.
#   Regenerate with:  npm run codegen   (from the insimul-runtime root)
#   Source of truth:  packages/core/schemas/{save-file,save-envelope,world-ir}.schema.json
#   Emitter:          tools/codegen/emit-gdscript.mjs (Godot 4 GDScript)
#
#   These mirror the core save/world JSON contract for the Godot SDK. Freeform
#   sub-objects (additionalProperties) are typed as Dictionary; opaque lists as
#   Array. See generated/README.md for the hand-written boundary convention.
# -----------------------------------------------------------------------------

class_name InsimulSaveFile
extends RefCounted

class World extends RefCounted:
	const _KNOWN_KEYS := ["id", "name"]
	const _REQUIRED_KEYS := ["id", "name"]

	var id: String = ""
	var name: String = ""

	static func from_dict(d: Dictionary) -> World:
		var o := World.new()
		if typeof(d) != TYPE_DICTIONARY:
			push_warning("World.from_dict: expected Dictionary")
			return o
		for __key in _REQUIRED_KEYS:
			if not d.has(__key):
				push_warning("World.from_dict: missing required field '" + str(__key) + "'")
		for __key in d.keys():
			if not _KNOWN_KEYS.has(__key):
				push_warning("World.from_dict: unknown field '" + str(__key) + "'")
		if d.has("id"):
			o.id = str(d["id"])
		if d.has("name"):
			o.name = str(d["name"])
		return o

	func to_dict() -> Dictionary:
		var d := {}
		d["id"] = id
		d["name"] = name
		return d

class CurrentState extends RefCounted:
	const _KNOWN_KEYS := ["player", "quests", "npcs", "languageProgress", "prologFacts", "extensions"]
	const _REQUIRED_KEYS := ["player", "quests", "npcs", "languageProgress", "prologFacts", "extensions"]

	var player: Dictionary = {}
	var quests: Dictionary = {}
	var npcs: Dictionary = {}
	var language_progress: Dictionary = {}
	var prolog_facts: Array = []
	var extensions: Dictionary = {}

	static func from_dict(d: Dictionary) -> CurrentState:
		var o := CurrentState.new()
		if typeof(d) != TYPE_DICTIONARY:
			push_warning("CurrentState.from_dict: expected Dictionary")
			return o
		for __key in _REQUIRED_KEYS:
			if not d.has(__key):
				push_warning("CurrentState.from_dict: missing required field '" + str(__key) + "'")
		for __key in d.keys():
			if not _KNOWN_KEYS.has(__key):
				push_warning("CurrentState.from_dict: unknown field '" + str(__key) + "'")
		if d.has("player"):
			o.player = d["player"]
		if d.has("quests"):
			o.quests = d["quests"]
		if d.has("npcs"):
			o.npcs = d["npcs"]
		if d.has("languageProgress"):
			o.language_progress = d["languageProgress"]
		if d.has("prologFacts"):
			o.prolog_facts = d["prologFacts"]
		if d.has("extensions"):
			o.extensions = d["extensions"]
		return o

	func to_dict() -> Dictionary:
		var d := {}
		d["player"] = player
		d["quests"] = quests
		d["npcs"] = npcs
		d["languageProgress"] = language_progress
		d["prologFacts"] = prolog_facts
		d["extensions"] = extensions
		return d

class WorldSnapshot extends RefCounted:
	const _KNOWN_KEYS := ["world", "countries", "settlements", "characters", "lots", "quests", "rules", "actions", "grammars"]
	const _REQUIRED_KEYS := ["world"]

	var world: World = null
	var countries: Array = []
	var settlements: Array = []
	var characters: Array = []
	var lots: Array = []
	var quests: Array = []
	var rules: Array = []
	var actions: Array = []
	var grammars: Array = []

	static func from_dict(d: Dictionary) -> WorldSnapshot:
		var o := WorldSnapshot.new()
		if typeof(d) != TYPE_DICTIONARY:
			push_warning("WorldSnapshot.from_dict: expected Dictionary")
			return o
		for __key in _REQUIRED_KEYS:
			if not d.has(__key):
				push_warning("WorldSnapshot.from_dict: missing required field '" + str(__key) + "'")
		for __key in d.keys():
			if not _KNOWN_KEYS.has(__key):
				push_warning("WorldSnapshot.from_dict: unknown field '" + str(__key) + "'")
		if d.has("world"):
			if d["world"] != null:
				o.world = World.from_dict(d["world"])
		if d.has("countries"):
			o.countries = d["countries"]
		if d.has("settlements"):
			o.settlements = d["settlements"]
		if d.has("characters"):
			o.characters = d["characters"]
		if d.has("lots"):
			o.lots = d["lots"]
		if d.has("quests"):
			o.quests = d["quests"]
		if d.has("rules"):
			o.rules = d["rules"]
		if d.has("actions"):
			o.actions = d["actions"]
		if d.has("grammars"):
			o.grammars = d["grammars"]
		return o

	func to_dict() -> Dictionary:
		var d := {}
		if world != null:
			d["world"] = world.to_dict()
		d["countries"] = countries
		d["settlements"] = settlements
		d["characters"] = characters
		d["lots"] = lots
		d["quests"] = quests
		d["rules"] = rules
		d["actions"] = actions
		d["grammars"] = grammars
		return d

const STATUS_VALUES := ["active", "completed", "abandoned"]
const _KNOWN_KEYS := ["id", "slotIndex", "userId", "worldId", "name", "version", "status", "createdAt", "lastSavedAt", "totalPlaytime", "saveCount", "worldSnapshot", "currentState", "conversations", "previousSnapshots"]
const _REQUIRED_KEYS := ["id", "slotIndex", "userId", "worldId", "name", "version", "status", "createdAt", "lastSavedAt", "totalPlaytime", "saveCount", "worldSnapshot", "currentState", "conversations"]

var id: String = ""
var slot_index: int = 0
var user_id: String = ""
var world_id: String = ""
var name: String = ""
var version: int = 0
var status: String = ""
var created_at: String = ""
var last_saved_at: String = ""
var total_playtime: float = 0.0
var save_count: int = 0
var world_snapshot: WorldSnapshot = null
var current_state: CurrentState = null
var conversations: Array = []
var previous_snapshots: Array = []

static func from_dict(d: Dictionary) -> InsimulSaveFile:
	var o := InsimulSaveFile.new()
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("InsimulSaveFile.from_dict: expected Dictionary")
		return o
	for __key in _REQUIRED_KEYS:
		if not d.has(__key):
			push_warning("InsimulSaveFile.from_dict: missing required field '" + str(__key) + "'")
	for __key in d.keys():
		if not _KNOWN_KEYS.has(__key):
			push_warning("InsimulSaveFile.from_dict: unknown field '" + str(__key) + "'")
	if d.has("id"):
		o.id = str(d["id"])
	if d.has("slotIndex"):
		o.slot_index = int(d["slotIndex"])
	if d.has("userId"):
		o.user_id = str(d["userId"])
	if d.has("worldId"):
		o.world_id = str(d["worldId"])
	if d.has("name"):
		o.name = str(d["name"])
	if d.has("version"):
		o.version = int(d["version"])
	if d.has("status"):
		o.status = str(d["status"])
		if not STATUS_VALUES.has(o.status):
			push_warning("InsimulSaveFile.from_dict: field 'status' has invalid value '" + o.status + "'")
	if d.has("createdAt"):
		o.created_at = str(d["createdAt"])
	if d.has("lastSavedAt"):
		o.last_saved_at = str(d["lastSavedAt"])
	if d.has("totalPlaytime"):
		o.total_playtime = float(d["totalPlaytime"])
	if d.has("saveCount"):
		o.save_count = int(d["saveCount"])
	if d.has("worldSnapshot"):
		if d["worldSnapshot"] != null:
			o.world_snapshot = WorldSnapshot.from_dict(d["worldSnapshot"])
	if d.has("currentState"):
		if d["currentState"] != null:
			o.current_state = CurrentState.from_dict(d["currentState"])
	if d.has("conversations"):
		o.conversations = d["conversations"]
	if d.has("previousSnapshots"):
		o.previous_snapshots = d["previousSnapshots"]
	return o

func to_dict() -> Dictionary:
	var d := {}
	d["id"] = id
	d["slotIndex"] = slot_index
	d["userId"] = user_id
	d["worldId"] = world_id
	d["name"] = name
	d["version"] = version
	d["status"] = status
	d["createdAt"] = created_at
	d["lastSavedAt"] = last_saved_at
	d["totalPlaytime"] = total_playtime
	d["saveCount"] = save_count
	if world_snapshot != null:
		d["worldSnapshot"] = world_snapshot.to_dict()
	if current_state != null:
		d["currentState"] = current_state.to_dict()
	d["conversations"] = conversations
	d["previousSnapshots"] = previous_snapshots
	return d
