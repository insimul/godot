extends Node
## Game Clock — autoloaded singleton.
## Tracks in-game time (hour of day, day count) with configurable speed.
## Emits EventBus time events when hour or day changes.

## Current fractional hour (0.0–23.999...)
var current_hour: float = 6.0

## Current day count (starts at 1)
var day: int = 1

## Game-seconds per real-second (60 = 1 game-minute per real-second)
var time_scale: float = 60.0

## When true, time does not advance
var is_paused: bool = false

var _previous_hour_int: int = -1

func _ready() -> void:
	_previous_hour_int = int(current_hour)

func _process(delta: float) -> void:
	if is_paused:
		return
	var hours_delta := (delta * time_scale) / 3600.0
	current_hour += hours_delta
	if current_hour >= 24.0:
		current_hour -= 24.0
		day += 1
		EventBus.emit_event({"type": "day_changed", "day": day, "timestep": 0})
	var hour_int := int(current_hour)
	if hour_int != _previous_hour_int:
		_previous_hour_int = hour_int
		EventBus.emit_event({"type": "hour_changed", "hour": hour_int, "day": day})
