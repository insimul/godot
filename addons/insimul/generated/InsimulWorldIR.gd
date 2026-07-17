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

class_name InsimulWorldIR
extends RefCounted

class Meta extends RefCounted:
	const _KNOWN_KEYS := ["insimulVersion", "worldId", "worldName", "worldType", "genreConfig", "exportTimestamp", "exportVersion", "seed"]
	const _REQUIRED_KEYS := ["insimulVersion", "worldId", "worldName", "worldType", "genreConfig", "exportTimestamp", "exportVersion", "seed"]

	var insimul_version: String = ""
	var world_id: String = ""
	var world_name: String = ""
	var world_type: String = ""
	var genre_config: Dictionary = {}
	var export_timestamp: String = ""
	var export_version: int = 0
	var seed: String = ""

	static func from_dict(d: Dictionary) -> Meta:
		var o := Meta.new()
		if typeof(d) != TYPE_DICTIONARY:
			push_warning("Meta.from_dict: expected Dictionary")
			return o
		for __key in _REQUIRED_KEYS:
			if not d.has(__key):
				push_warning("Meta.from_dict: missing required field '" + str(__key) + "'")
		for __key in d.keys():
			if not _KNOWN_KEYS.has(__key):
				push_warning("Meta.from_dict: unknown field '" + str(__key) + "'")
		if d.has("insimulVersion"):
			o.insimul_version = str(d["insimulVersion"])
		if d.has("worldId"):
			o.world_id = str(d["worldId"])
		if d.has("worldName"):
			o.world_name = str(d["worldName"])
		if d.has("worldType"):
			o.world_type = str(d["worldType"])
		if d.has("genreConfig"):
			o.genre_config = d["genreConfig"]
		if d.has("exportTimestamp"):
			o.export_timestamp = str(d["exportTimestamp"])
		if d.has("exportVersion"):
			o.export_version = int(d["exportVersion"])
		if d.has("seed"):
			o.seed = str(d["seed"])
		return o

	func to_dict() -> Dictionary:
		var d := {}
		d["insimulVersion"] = insimul_version
		d["worldId"] = world_id
		d["worldName"] = world_name
		d["worldType"] = world_type
		d["genreConfig"] = genre_config
		d["exportTimestamp"] = export_timestamp
		d["exportVersion"] = export_version
		d["seed"] = seed
		return d

const _KNOWN_KEYS := ["meta", "geography", "entities", "systems", "theme", "assets", "player", "ui", "combat", "survival", "resources", "assessment", "languageLearning", "aiConfig"]
const _REQUIRED_KEYS := ["meta", "geography", "entities", "systems", "theme", "assets", "player", "ui", "combat", "survival", "resources", "assessment", "languageLearning", "aiConfig"]

var meta: Meta = null
var geography: Dictionary = {}
var entities: Dictionary = {}
var systems: Dictionary = {}
var theme: Dictionary = {}
var assets: Dictionary = {}
var player: Dictionary = {}
var ui: Dictionary = {}
var combat: Dictionary = {}
var survival = {}
var resources = {}
var assessment = {}
var language_learning = {}
var ai_config: Dictionary = {}

static func from_dict(d: Dictionary) -> InsimulWorldIR:
	var o := InsimulWorldIR.new()
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("InsimulWorldIR.from_dict: expected Dictionary")
		return o
	for __key in _REQUIRED_KEYS:
		if not d.has(__key):
			push_warning("InsimulWorldIR.from_dict: missing required field '" + str(__key) + "'")
	for __key in d.keys():
		if not _KNOWN_KEYS.has(__key):
			push_warning("InsimulWorldIR.from_dict: unknown field '" + str(__key) + "'")
	if d.has("meta"):
		if d["meta"] != null:
			o.meta = Meta.from_dict(d["meta"])
	if d.has("geography"):
		o.geography = d["geography"]
	if d.has("entities"):
		o.entities = d["entities"]
	if d.has("systems"):
		o.systems = d["systems"]
	if d.has("theme"):
		o.theme = d["theme"]
	if d.has("assets"):
		o.assets = d["assets"]
	if d.has("player"):
		o.player = d["player"]
	if d.has("ui"):
		o.ui = d["ui"]
	if d.has("combat"):
		o.combat = d["combat"]
	if d.has("survival"):
		o.survival = d["survival"]
	if d.has("resources"):
		o.resources = d["resources"]
	if d.has("assessment"):
		o.assessment = d["assessment"]
	if d.has("languageLearning"):
		o.language_learning = d["languageLearning"]
	if d.has("aiConfig"):
		o.ai_config = d["aiConfig"]
	return o

func to_dict() -> Dictionary:
	var d := {}
	if meta != null:
		d["meta"] = meta.to_dict()
	d["geography"] = geography
	d["entities"] = entities
	d["systems"] = systems
	d["theme"] = theme
	d["assets"] = assets
	d["player"] = player
	d["ui"] = ui
	d["combat"] = combat
	d["survival"] = survival
	d["resources"] = resources
	d["assessment"] = assessment
	d["languageLearning"] = language_learning
	d["aiConfig"] = ai_config
	return d
