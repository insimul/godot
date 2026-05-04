extends Node3D
## Ranged Combat System — projectile/hitscan weapons with ammo and spread.
## Used when combat_style is "ranged" or "shooter".

signal weapon_fired(weapon_id: String, ammo_remaining: int)
signal weapon_reloading(weapon_id: String, reload_time: float)
signal weapon_reloaded(weapon_id: String)
signal hit_confirmed(target_id: String, damage: float, is_headshot: bool)
signal weapon_switched(weapon_id: String)

## Weapon configurations
const WEAPONS := {
	"pistol": {"damage": 15, "range": 50.0, "fire_rate": 3.0, "magazine": 12, "reload_time": 1.5, "projectile_speed": 0.0, "spread": 0.02, "pellets": 1, "name": "Pistol"},
	"rifle": {"damage": 30, "range": 100.0, "fire_rate": 1.5, "magazine": 8, "reload_time": 2.5, "projectile_speed": 0.0, "spread": 0.005, "pellets": 1, "name": "Rifle"},
	"shotgun": {"damage": 8, "range": 25.0, "fire_rate": 1.0, "magazine": 6, "reload_time": 3.0, "projectile_speed": 0.0, "spread": 0.15, "pellets": 8, "name": "Shotgun"},
	"bow": {"damage": 25, "range": 60.0, "fire_rate": 0.8, "magazine": 1, "reload_time": 0.8, "projectile_speed": 40.0, "spread": 0.01, "pellets": 1, "name": "Bow"},
	"magic_staff": {"damage": 20, "range": 45.0, "fire_rate": 2.0, "magazine": 5, "reload_time": 2.0, "projectile_speed": 25.0, "spread": 0.03, "pellets": 1, "name": "Magic Staff"},
}

var _current_weapon := "pistol"
var _ammo: Dictionary = {}  # weapon_id → current ammo count
var _last_fire_time := -999.0
var _is_reloading := false
var _reload_timer := 0.0
var _active_projectiles: Array[Dictionary] = []  # [{node, direction, speed, damage, distance, max_range}]
var _player: Node3D = null
var _camera: Camera3D = null

func _ready() -> void:
	# Initialize ammo for all weapons
	for weapon_id in WEAPONS:
		_ammo[weapon_id] = WEAPONS[weapon_id]["magazine"]

func _process(delta: float) -> void:
	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0:
			_finish_reload()

	_update_projectiles(delta)

func switch_weapon(weapon_id: String) -> void:
	if not WEAPONS.has(weapon_id):
		return
	_current_weapon = weapon_id
	_is_reloading = false
	weapon_switched.emit(weapon_id)

func fire(origin: Vector3, direction: Vector3) -> void:
	if _is_reloading:
		return

	var weapon: Dictionary = WEAPONS[_current_weapon]
	var fire_interval: float = 1.0 / weapon["fire_rate"]
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_fire_time < fire_interval:
		return

	if _ammo[_current_weapon] <= 0:
		reload()
		return

	_last_fire_time = now
	_ammo[_current_weapon] -= 1

	var pellets: int = weapon.get("pellets", 1)
	for _i in range(pellets):
		var spread_dir := _apply_spread(direction, weapon["spread"])
		if weapon["projectile_speed"] > 0:
			_spawn_projectile(origin, spread_dir, weapon)
		else:
			_hitscan(origin, spread_dir, weapon)

	weapon_fired.emit(_current_weapon, _ammo[_current_weapon])

	# Auto-reload when empty
	if _ammo[_current_weapon] <= 0:
		reload()

func reload() -> void:
	if _is_reloading:
		return
	var weapon: Dictionary = WEAPONS[_current_weapon]
	if _ammo[_current_weapon] >= weapon["magazine"]:
		return
	_is_reloading = true
	_reload_timer = weapon["reload_time"]
	weapon_reloading.emit(_current_weapon, _reload_timer)

func _finish_reload() -> void:
	_is_reloading = false
	_ammo[_current_weapon] = WEAPONS[_current_weapon]["magazine"]
	weapon_reloaded.emit(_current_weapon)

# ─────────────────────────────────────────────
# Hitscan (instant raycast)
# ─────────────────────────────────────────────

func _hitscan(origin: Vector3, direction: Vector3, weapon: Dictionary) -> void:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return

	var end := origin + direction * weapon["range"]
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_areas = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider: Node = result.get("collider")
	if collider == null:
		return

	var damage: float = weapon["damage"]
	var hit_pos: Vector3 = result.get("position", end)

	# Check if we hit an NPC
	var target_id := ""
	var parent := collider.get_parent()
	if parent and parent.has_meta("character_id"):
		target_id = parent.get_meta("character_id")
	elif collider.has_meta("character_id"):
		target_id = collider.get_meta("character_id")

	if target_id != "":
		hit_confirmed.emit(target_id, damage, false)
		EventBus.emit_event({
			"type": "combat_action",
			"action_type": "ranged_%s" % _current_weapon,
			"damage": int(damage),
			"target_id": target_id,
		})

# ─────────────────────────────────────────────
# Projectile physics
# ─────────────────────────────────────────────

func _spawn_projectile(origin: Vector3, direction: Vector3, weapon: Dictionary) -> void:
	var projectile := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	projectile.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	projectile.material_override = mat
	projectile.position = origin
	add_child(projectile)

	_active_projectiles.append({
		"node": projectile,
		"direction": direction.normalized(),
		"speed": weapon["projectile_speed"],
		"damage": weapon["damage"],
		"distance": 0.0,
		"max_range": weapon["range"],
	})

func _update_projectiles(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(_active_projectiles.size()):
		var proj: Dictionary = _active_projectiles[i]
		var node: MeshInstance3D = proj["node"]
		if not is_instance_valid(node):
			to_remove.append(i)
			continue

		var move: Vector3 = proj["direction"] * proj["speed"] * delta
		node.position += move
		proj["distance"] += move.length()

		# Out of range
		if proj["distance"] >= proj["max_range"]:
			to_remove.append(i)
			node.queue_free()
			continue

		# Simple proximity collision check
		var space_state := get_world_3d().direct_space_state
		if space_state:
			var query := PhysicsRayQueryParameters3D.create(
				node.position - move, node.position
			)
			var result := space_state.intersect_ray(query)
			if not result.is_empty():
				var collider: Node = result.get("collider")
				if collider:
					var target_id := ""
					var parent := collider.get_parent()
					if parent and parent.has_meta("character_id"):
						target_id = parent.get_meta("character_id")
					if target_id != "":
						hit_confirmed.emit(target_id, proj["damage"], false)
						EventBus.emit_event({
							"type": "combat_action",
							"action_type": "ranged_%s" % _current_weapon,
							"damage": int(proj["damage"]),
							"target_id": target_id,
						})
				to_remove.append(i)
				node.queue_free()

	for i in range(to_remove.size() - 1, -1, -1):
		_active_projectiles.remove_at(to_remove[i])

# ─────────────────────────────────────────────
# Spread calculation
# ─────────────────────────────────────────────

func _apply_spread(direction: Vector3, spread: float) -> Vector3:
	if spread <= 0:
		return direction
	var theta: float = (randf() - 0.5) * 2.0 * spread
	var phi: float = (randf() - 0.5) * 2.0 * spread
	var basis := Basis.looking_at(direction, Vector3.UP)
	return (basis * Vector3(sin(theta), sin(phi), 1.0)).normalized()

# ─────────────────────────────────────────────
# Queries
# ─────────────────────────────────────────────

func get_current_weapon() -> Dictionary:
	return WEAPONS.get(_current_weapon, {})

func get_current_weapon_id() -> String:
	return _current_weapon

func get_ammo() -> int:
	return _ammo.get(_current_weapon, 0)

func get_magazine_size() -> int:
	return WEAPONS.get(_current_weapon, {}).get("magazine", 0)

func is_reloading() -> bool:
	return _is_reloading
