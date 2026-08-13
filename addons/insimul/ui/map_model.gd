class_name InsimulMapModel
extends RefCounted
## Map view-model shared by the minimap and the full map (US-GU2).
##
## The minimap and the full map are two viewports onto ONE data set: the world
## bounds, the player position, and the point-of-interest markers. Both panels
## read this model, so a marker that shows on one shows on the other and the two
## can never disagree about where it is.
##
## Everything here is pure arithmetic on plain data — no SubViewport, no Camera3D,
## no raycast. The engine-side capture (the template's minimap.gd renders the world
## through a SubViewport) belongs in `templates/`; the addon owns the projection and
## the marker set, which is what a test can execute.
##
## A marker is { id, kind, x, z, label? }. `kind` is a creator vocabulary — the
## model never spells one, it only filters by what it is given.

const MARKER_KEY := "id"

var _min_x := 0.0
var _min_z := 0.0
var _max_x := 1.0
var _max_z := 1.0
var _markers: Dictionary = {}      # id -> marker Dictionary
var _order: Array[String] = []
var _player := Vector2.ZERO


## Set the world rectangle the map covers. A degenerate rectangle (zero width or
## depth) is widened to 1 unit so [method to_map] never divides by zero.
func set_bounds(min_x: float, min_z: float, max_x: float, max_z: float) -> void:
	_min_x = min_x
	_min_z = min_z
	_max_x = max_x if max_x > min_x else min_x + 1.0
	_max_z = max_z if max_z > min_z else min_z + 1.0


func bounds() -> Rect2:
	return Rect2(_min_x, _min_z, _max_x - _min_x, _max_z - _min_z)


## World (x, z) -> normalized map space, (0,0) top-left to (1,1) bottom-right.
## Positions outside the bounds are NOT clamped: a caller that wants a marker
## pinned to the edge clamps it, and one that wants it hidden tests the range.
func to_map(world_x: float, world_z: float) -> Vector2:
	return Vector2(
		(world_x - _min_x) / (_max_x - _min_x),
		(world_z - _min_z) / (_max_z - _min_z)
	)


## Normalized map space -> world (x, z). The inverse of [method to_map]; this is
## what a click on the full map answers.
func to_world(map_point: Vector2) -> Vector2:
	return Vector2(
		_min_x + map_point.x * (_max_x - _min_x),
		_min_z + map_point.y * (_max_z - _min_z)
	)


func is_inside(world_x: float, world_z: float) -> bool:
	return world_x >= _min_x and world_x <= _max_x and world_z >= _min_z and world_z <= _max_z


# ── Markers ───────────────────────────────────────────────────────────────────

## Replace the whole marker set, preserving the given order.
func set_markers(markers: Array) -> void:
	_markers.clear()
	_order.clear()
	for m in markers:
		upsert_marker(m)


## Add or replace a marker by id. A new id is appended so draw order is stable.
func upsert_marker(marker: Dictionary) -> void:
	var id := String(marker.get(MARKER_KEY, ""))
	if id.is_empty():
		return
	if not _markers.has(id):
		_order.append(id)
	_markers[id] = marker.duplicate(true)


func remove_marker(id: String) -> bool:
	if not _markers.has(id):
		return false
	_markers.erase(id)
	_order.erase(id)
	return true


## Every marker, in insertion order.
func markers() -> Array:
	var out: Array = []
	for id in _order:
		out.append((_markers[id] as Dictionary).duplicate(true))
	return out


## Markers whose `kind` is in `kinds`. An empty `kinds` means every marker — a
## filter nobody set is not a filter that hides everything.
func markers_of_kind(kinds: Array) -> Array:
	if kinds.is_empty():
		return markers()
	var wanted := {}
	for k in kinds:
		wanted[String(k)] = true
	var out: Array = []
	for m in markers():
		if wanted.has(String(m.get("kind", ""))):
			out.append(m)
	return out


## Markers within `radius` world units of (x, z) — what the minimap draws while
## the full map draws them all.
func markers_near(world_x: float, world_z: float, radius: float) -> Array:
	var out: Array = []
	var origin := Vector2(world_x, world_z)
	for m in markers():
		if origin.distance_to(Vector2(float(m.get("x", 0.0)), float(m.get("z", 0.0)))) <= radius:
			out.append(m)
	return out


# ── Player ────────────────────────────────────────────────────────────────────

func set_player_position(world_x: float, world_z: float) -> void:
	_player = Vector2(world_x, world_z)


func player_position() -> Vector2:
	return _player


## The player in normalized map space — where both panels put the "you are here".
func player_map_point() -> Vector2:
	return to_map(_player.x, _player.y)
