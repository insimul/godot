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

class_name InsimulSaveFileEnvelope
extends RefCounted

const _KNOWN_KEYS := ["format", "exportedAt", "insimulVersion", "saveFile", "integrity"]
const _REQUIRED_KEYS := ["format", "exportedAt", "insimulVersion", "saveFile", "integrity"]

var format: String = ""
var exported_at: String = ""
var insimul_version: String = ""
var save_file: InsimulSaveFile = null
var integrity: String = ""

static func from_dict(d: Dictionary) -> InsimulSaveFileEnvelope:
	var o := InsimulSaveFileEnvelope.new()
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("InsimulSaveFileEnvelope.from_dict: expected Dictionary")
		return o
	for __key in _REQUIRED_KEYS:
		if not d.has(__key):
			push_warning("InsimulSaveFileEnvelope.from_dict: missing required field '" + str(__key) + "'")
	for __key in d.keys():
		if not _KNOWN_KEYS.has(__key):
			push_warning("InsimulSaveFileEnvelope.from_dict: unknown field '" + str(__key) + "'")
	if d.has("format"):
		o.format = str(d["format"])
	if d.has("exportedAt"):
		o.exported_at = str(d["exportedAt"])
	if d.has("insimulVersion"):
		o.insimul_version = str(d["insimulVersion"])
	if d.has("saveFile"):
		if d["saveFile"] != null:
			o.save_file = InsimulSaveFile.from_dict(d["saveFile"])
	if d.has("integrity"):
		o.integrity = str(d["integrity"])
	return o

func to_dict() -> Dictionary:
	var d := {}
	d["format"] = format
	d["exportedAt"] = exported_at
	d["insimulVersion"] = insimul_version
	if save_file != null:
		d["saveFile"] = save_file.to_dict()
	d["integrity"] = integrity
	return d
