class_name InsimulLoadingScreenModel
extends RefCounted
## Loading-screen view-model driven by the runtime startup phases (US-GU1).
##
## The boot loop (world source -> save slot -> KB -> systems init; see
## runtime_bootstrap.gd / gdextension/src/bootstrap.h) advances this model through
## an ordered set of weighted phases. The model turns the current phase into a
## MONOTONIC progress fraction in [0, 1], a human label, and a deterministic tip.
##
## Contract + shared cases: packages/core/conformance/ui/loading-phases.json. The
## same weighted-cumulative-progress rule is asserted by every default-UI mirror
## (Babylon / Unity / Unreal), so the default phase table below MUST match the
## corpus. A custom table can be injected (e.g. by the parity test) via the
## constructor.

## Ordered default phases: { key, label, weight }. Progress at a phase is the
## cumulative weight through that phase divided by the total weight. Mirrors
## packages/core/conformance/ui/loading-phases.json → `phases`.
const DEFAULT_PHASES: Array = [
	{"key": "init", "label": "Starting up…", "weight": 1},
	{"key": "world", "label": "Loading world…", "weight": 3},
	{"key": "save", "label": "Restoring save…", "weight": 2},
	{"key": "kb", "label": "Building knowledge base…", "weight": 2},
	{"key": "systems", "label": "Initializing systems…", "weight": 1},
	{"key": "ready", "label": "Ready", "weight": 1},
]

## Deterministic tip pool. tip() returns the tip at (phase index % tips.size()).
const DEFAULT_TIPS: Array = [
	"Talk to villagers to uncover radiant quests.",
	"Every conversation is generated live — no two runs are alike.",
	"Check the quest journal (J) to track objectives.",
	"Your progress autosaves to the active slot.",
]

var _phases: Array = DEFAULT_PHASES
var _tips: Array = DEFAULT_TIPS
var _total_weight: int = 0
var _current_key: String = ""
var _progress: float = 0.0


## Optional injection of a custom phase table / tip pool (used by the parity test
## to run the shared corpus). Each phase entry is { key, label, weight }.
func _init(phases: Array = DEFAULT_PHASES, tips: Array = DEFAULT_TIPS) -> void:
	_phases = phases if not phases.is_empty() else DEFAULT_PHASES
	_tips = tips if not tips.is_empty() else DEFAULT_TIPS
	_total_weight = 0
	for phase in _phases:
		_total_weight += int(phase.get("weight", 0))
	if _total_weight <= 0:
		_total_weight = 1


## Advance to a named phase. Progress is clamped to be monotonic — re-entering the
## current phase, or a phase earlier in the order, never lowers the bar.
func advance(key: String) -> void:
	var idx := _index_of(key)
	if idx < 0:
		return
	_current_key = key
	var cumulative := 0
	for i in range(idx + 1):
		cumulative += int(_phases[i].get("weight", 0))
	var next_progress := float(cumulative) / float(_total_weight)
	_progress = max(_progress, next_progress)


func progress() -> float:
	return _progress


func label() -> String:
	var idx := _index_of(_current_key)
	if idx < 0:
		return ""
	return String(_phases[idx].get("label", ""))


## Deterministic per-phase tip (index by phase position, wrapping the tip pool).
func tip() -> String:
	var idx := _index_of(_current_key)
	if idx < 0 or _tips.is_empty():
		return ""
	return String(_tips[idx % _tips.size()])


func current_phase() -> String:
	return _current_key


## True once the final (terminal) phase has been reached.
func is_complete() -> bool:
	if _phases.is_empty():
		return false
	return _current_key == String(_phases[_phases.size() - 1].get("key", ""))


func reset() -> void:
	_current_key = ""
	_progress = 0.0


func _index_of(key: String) -> int:
	for i in range(_phases.size()):
		if String(_phases[i].get("key", "")) == key:
			return i
	return -1
