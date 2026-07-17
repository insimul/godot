class_name InsimulSaveSlotModel
extends RefCounted
## Save / load slot view-model (US-GU3).
##
## The Godot mirror of the engine-neutral save/load slot contract
## (packages/core/src/ui/save-slot-model.ts). A slot is loaded by the codec
## (insimul_save_codec) into an OUTCOME — empty / ok (+ summary) / one of the
## envelope validation failures — and this model renders each into a row
## (status/title/message/can_load/can_save). The corrupted-envelope MESSAGING is the
## cross-engine contract. Shared cases:
## packages/core/conformance/ui/save-slot-cases.json.

## Human, cross-engine messaging for each non-ok outcome (keep in lockstep with the
## TS SLOT_MESSAGES map).
const MESSAGES := {
	"empty": "",
	"ok": "",
	"invalid_format": "Unrecognized save format — this slot cannot be loaded.",
	"missing_save_file": "Save data is missing or unreadable.",
	"integrity_mismatch": "Save file integrity check failed — file may be corrupted or tampered.",
}

var _results: Array = []            # [{ index, outcome, summary? }]


func _init(results: Array = []) -> void:
	set_slots(results)


func set_slots(results: Array) -> void:
	_results = []
	for r in results:
		_results.append((r as Dictionary).duplicate(true))


static func _summary_title(index: int, summary: Dictionary) -> String:
	if summary.is_empty():
		return "Slot %d" % (index + 1)
	var bits: Array = []
	if summary.has("playerName") and String(summary["playerName"]) != "":
		bits.append(String(summary["playerName"]))
	if summary.has("level"):
		bits.append("Lv %d" % int(summary["level"]))
	if summary.has("locationName") and String(summary["locationName"]) != "":
		bits.append(String(summary["locationName"]))
	if bits.is_empty():
		return "Slot %d" % (index + 1)
	return " · ".join(bits)


static func _view(result: Dictionary) -> Dictionary:
	var index := int(result.get("index", 0))
	var outcome := String(result.get("outcome", "empty"))
	var summary: Dictionary = result.get("summary", {})
	if outcome == "empty":
		return {"index": index, "status": "empty", "title": "Empty Slot", "message": "",
			"can_load": false, "can_save": true}
	if outcome == "ok":
		var message := ""
		if summary.has("savedAt") and String(summary["savedAt"]) != "":
			message = "Saved %s" % String(summary["savedAt"])
		return {"index": index, "status": "ok", "title": _summary_title(index, summary),
			"message": message, "can_load": true, "can_save": true, "summary": summary}
	# Any validation failure -> corrupted. Cannot load, but can overwrite.
	return {"index": index, "status": "corrupted", "title": "Corrupted Save",
		"message": String(MESSAGES.get(outcome, "")), "can_load": false, "can_save": true}


## The rendered rows, in slot-index order.
func slots() -> Array:
	var sorted := _results.duplicate(true)
	sorted.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
	var out: Array = []
	for r in sorted:
		out.append(_view(r))
	return out


func slot(index: int) -> Dictionary:
	for r in _results:
		if int(r.get("index", 0)) == index:
			return _view(r)
	return {}


## True when any slot is loadable (main-menu Continue gate).
func has_any_loadable() -> bool:
	for r in _results:
		if String(r.get("outcome", "")) == "ok":
			return true
	return false
