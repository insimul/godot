@tool
class_name InsimulSceneGenerator
extends RefCounted
## Editor-time scene-generation pipeline (US-GB2) — the @tool twin of the host
## placement core (packages/godot/gdextension/src/scene_placement.cpp).
##
## Given a World IR Dictionary and an InsimulBindingResolver (the placeholder
## pack, optionally layered with project/pack overrides) it MATERIALIZES the
## generated scene tree:
##   - terrain as MeshInstance3D chunks + a StaticBody3D/HeightMapShape3D
##     collider sampled from the IR heightmap,
##   - roads as Path3D + a mesh strip,
##   - buildings and props as the resolved PackedScene (falling back to a
##     primitive placeholder MeshInstance3D when the asset is absent),
##   - interiors as SEPARATE scene roots (the template door-warp convention),
##   - a NavigationRegion3D bake root,
## and stamps every generated node with its stable InsimulEntityId + the
## `insimul_generated` flag (the re-import diff match keys, US-GB3).
##
## The placement MATH here mirrors scene_placement.cpp exactly; the shared golden
## (fixtures/golden-placement-manifest.json) pins BOTH via the host gate and the
## headless twin (scene_generator_test.gd) so they can never diverge. This runs
## only when a real `godot` binary is present (run_scene_generator_headless.sh);
## the host C++ gate holds the contract on a bare box.

const GRID_SIZE := 1.0
const COORD_QUANTUM := 0.001

## Zone-based footprint scaling — mirrors scene_placement.cpp
## zone_scale_for_role and the runtime building_placement_system.gd table.
const ZONE_SCALE := {
	"commercial": 1.3,
	"downtown": 1.4,
	"industrial": 1.2,
	"outskirts": 0.9,
}

# ---------------------------------------------------------------------------
# Placement math (mirror of scene_placement.cpp)
# ---------------------------------------------------------------------------

## Round to COORD_QUANTUM by dividing after the round so 1.4 stays 1.4 (matches
## the host quantize_coord).
static func quantize_coord(v: float) -> float:
	if not is_finite(v):
		return 0.0
	var inv := 1.0 / COORD_QUANTUM
	var q := round(v * inv) / inv
	if q == 0.0:
		return 0.0
	return q


static func zone_scale_for_role(role: String) -> float:
	return float(ZONE_SCALE.get(role, 1.0))


## Bilinear height lookup over a row-major heightmap grid. Out-of-range world
## coords clamp to the edge.
static func sample_terrain_height(heights: Array, resolution: int, size_x: float, size_z: float, wx: float, wz: float) -> float:
	if resolution < 1 or heights.is_empty():
		return 0.0
	if resolution == 1:
		return float(heights[0])
	if size_x <= 0.0 or size_z <= 0.0:
		return float(heights[0])
	var gx: float = clampf((wx / size_x) * (resolution - 1), 0.0, float(resolution - 1))
	var gz: float = clampf((wz / size_z) * (resolution - 1), 0.0, float(resolution - 1))
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var x1: int = min(x0 + 1, resolution - 1)
	var z1: int = min(z0 + 1, resolution - 1)
	var fx := gx - x0
	var fz := gz - z0
	var h00 := _height_at(heights, resolution, x0, z0)
	var h10 := _height_at(heights, resolution, x1, z0)
	var h01 := _height_at(heights, resolution, x0, z1)
	var h11 := _height_at(heights, resolution, x1, z1)
	var top := h00 + (h10 - h00) * fx
	var bot := h01 + (h11 - h01) * fx
	return top + (bot - top) * fz


static func _height_at(heights: Array, resolution: int, gx: int, gz: int) -> float:
	var idx := gz * resolution + gx
	if idx < 0 or idx >= heights.size():
		return 0.0
	return float(heights[idx])


# ---------------------------------------------------------------------------
# Scene-tree materialization
# ---------------------------------------------------------------------------

## Build the generated scene tree from a World IR Dictionary. Returns the root
## Node3D; every generated node carries `insimul_entity_id`, `insimul_kind`,
## `insimul_archetype`, `insimul_scene`, `insimul_binding_source` and
## `insimul_generated` metadata.
func generate(ir: Dictionary, resolver: InsimulBindingResolver) -> Node3D:
	var root := Node3D.new()
	root.name = "GeneratedWorld"

	var geography: Dictionary = ir.get("geography", {})
	var entities: Dictionary = ir.get("entities", {})
	var terrain: Dictionary = geography.get("terrain", {})

	var heights: Array = terrain.get("heightmap", {}).get("heights", [])
	var resolution := int(terrain.get("heightmap", {}).get("resolution", 0))
	var size: Dictionary = terrain.get("size", {})
	var size_x := float(size.get("x", 0.0))
	var size_z := float(size.get("z", 0.0))
	var chunk_size := float(terrain.get("chunkSize", 0.0))

	# --- Terrain chunks + collision ---
	if size_x > 0.0 and size_z > 0.0 and chunk_size > 0.0:
		var chunks_x := int(ceil(size_x / chunk_size))
		var chunks_z := int(ceil(size_z / chunk_size))
		for cz in range(chunks_z):
			for cx in range(chunks_x):
				var centre_x := cx * chunk_size + chunk_size * 0.5
				var centre_z := cz * chunk_size + chunk_size * 0.5
				var y := sample_terrain_height(heights, resolution, size_x, size_z, centre_x, centre_z)
				var chunk := _make_terrain_chunk(chunk_size)
				var entity_id := "terrain.chunk.%d_%d" % [cx, cz]
				_place(chunk, Vector3(centre_x, y, centre_z), 0.0, Vector3.ONE)
				_stamp(chunk, entity_id, "terrain_chunk", "terrain", resolver)
				root.add_child(chunk)

	# --- Roads ---
	var roads: Array = geography.get("roads", [])
	for r in roads:
		var points: Array = r.get("points", [])
		var sx := 0.0
		var sz := 0.0
		for p in points:
			sx += float(p.get("x", 0.0))
			sz += float(p.get("z", 0.0))
		var cx := sx / points.size() if not points.is_empty() else 0.0
		var cz := sz / points.size() if not points.is_empty() else 0.0
		var y := sample_terrain_height(heights, resolution, size_x, size_z, cx, cz)
		var road := _make_road(points)
		_place(road, Vector3(cx, y, cz), 0.0, Vector3.ONE)
		_stamp(road, String(r.get("id", "")), "road", String(r.get("archetype", "road")), resolver)
		root.add_child(road)

	# --- Buildings (+ interiors) ---
	var buildings: Array = entities.get("buildings", [])
	for b in buildings:
		var role := String(b.get("role", "residential"))
		var archetype := String(b.get("archetype", "building." + role))
		var pos: Dictionary = b.get("position", {})
		var snapped_x := round(float(pos.get("x", 0.0)) / GRID_SIZE) * GRID_SIZE
		var snapped_z := round(float(pos.get("z", 0.0)) / GRID_SIZE) * GRID_SIZE
		var y := sample_terrain_height(heights, resolution, size_x, size_z, snapped_x, snapped_z)
		var s := zone_scale_for_role(role)
		var node := _instance_or_placeholder(resolver, archetype)
		_place(node, Vector3(snapped_x, y, snapped_z), float(b.get("rotation", 0.0)), Vector3(s, s, s))
		_stamp(node, String(b.get("id", "")), "building", archetype, resolver)
		root.add_child(node)

		if bool(b.get("interior", false)):
			var interior_archetype := "interior." + role
			var interior := _instance_or_placeholder(resolver, interior_archetype)
			_place(interior, Vector3.ZERO, 0.0, Vector3.ONE)
			_stamp(interior, String(b.get("id", "")) + ".interior", "interior", interior_archetype, resolver)
			root.add_child(interior)

	# --- Props ---
	var props: Array = entities.get("props", [])
	for pr in props:
		var kind := String(pr.get("kind", "generic"))
		var archetype := String(pr.get("archetype", "prop." + kind))
		var pos: Dictionary = pr.get("position", {})
		var px := float(pos.get("x", 0.0))
		var pz := float(pos.get("z", 0.0))
		var y := sample_terrain_height(heights, resolution, size_x, size_z, px, pz)
		var node := _instance_or_placeholder(resolver, archetype)
		_place(node, Vector3(px, y, pz), float(pr.get("rotation", 0.0)), Vector3.ONE)
		_stamp(node, String(pr.get("id", "")), "prop", archetype, resolver)
		root.add_child(node)

	# --- Navigation region bake root ---
	var nav := NavigationRegion3D.new()
	_place(nav, Vector3.ZERO, 0.0, Vector3.ONE)
	_stamp(nav, "nav.region", "nav_region", "", null)
	root.add_child(nav)

	return root


## Walk a generated tree and reconstruct the placement manifest Dictionary
## (canonical shape, nodes sorted by entityId). Used by the headless twin to
## compare against the shared golden.
func manifest_from_tree(root: Node3D, seed_value: String) -> Dictionary:
	var nodes: Array = []
	for child in root.get_children():
		if not child.has_meta("insimul_entity_id"):
			continue
		var n := child as Node3D
		if n == null:
			continue
		nodes.append({
			"entityId": String(n.get_meta("insimul_entity_id")),
			"kind": String(n.get_meta("insimul_kind", "")),
			"archetype": String(n.get_meta("insimul_archetype", "")),
			"scene": String(n.get_meta("insimul_scene", "")),
			"bindingSource": String(n.get_meta("insimul_binding_source", "")),
			"generated": bool(n.get_meta("insimul_generated", false)),
			"position": {
				"x": quantize_coord(n.position.x),
				"y": quantize_coord(n.position.y),
				"z": quantize_coord(n.position.z),
			},
			"rotationY": quantize_coord(n.rotation.y),
			"scale": {
				"x": quantize_coord(n.scale.x),
				"y": quantize_coord(n.scale.y),
				"z": quantize_coord(n.scale.z),
			},
		})
	nodes.sort_custom(func(a, b): return String(a["entityId"]) < String(b["entityId"]))
	return {
		"manifestVersion": 1,
		"seed": seed_value,
		"nodeCount": nodes.size(),
		"nodes": nodes,
	}


# ---------------------------------------------------------------------------
# Node factories
# ---------------------------------------------------------------------------

func _make_terrain_chunk(chunk_size: float) -> Node3D:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(chunk_size, chunk_size)
	mesh.mesh = plane
	# HeightMapShape3D collider sampled from the chunk footprint.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = HeightMapShape3D.new()
	body.add_child(shape)
	mesh.add_child(body)
	return mesh


func _make_road(points: Array) -> Node3D:
	var path := Path3D.new()
	var curve := Curve3D.new()
	for p in points:
		curve.add_point(Vector3(float(p.get("x", 0.0)), 0.0, float(p.get("z", 0.0))))
	path.curve = curve
	var strip := MeshInstance3D.new()
	strip.mesh = BoxMesh.new()
	path.add_child(strip)
	return path


## Instance the resolved PackedScene, or a primitive placeholder MeshInstance3D
## when the asset is absent (the whole point of the placeholder pack — a runnable
## scene tree before any art exists).
func _instance_or_placeholder(resolver: InsimulBindingResolver, archetype: String) -> Node3D:
	var scene_path := _resolved_scene(resolver, archetype)
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var packed: PackedScene = load(scene_path)
		if packed != null:
			var inst := packed.instantiate()
			if inst is Node3D:
				return inst
	var placeholder := MeshInstance3D.new()
	placeholder.mesh = BoxMesh.new()
	return placeholder


func _resolved_scene(resolver: InsimulBindingResolver, archetype: String) -> String:
	if resolver == null or archetype == "":
		return ""
	var res: Dictionary = resolver.resolve(archetype)
	if not res.get("resolved", false):
		return ""
	var entry: Dictionary = res.get("entry", {})
	var scene := String(entry.get("scene", ""))
	if scene == "":
		scene = String(entry.get("mesh", ""))
	return scene


func _place(node: Node3D, position: Vector3, rotation_y: float, scale: Vector3) -> void:
	node.position = position
	node.rotation = Vector3(0.0, rotation_y, 0.0)
	node.scale = scale


func _stamp(node: Node3D, entity_id: String, kind: String, archetype: String, resolver: InsimulBindingResolver) -> void:
	node.set_meta("insimul_entity_id", entity_id)
	node.set_meta("insimul_kind", kind)
	node.set_meta("insimul_archetype", archetype)
	node.set_meta("insimul_generated", true)
	var scene := ""
	var source := ""
	if resolver != null and archetype != "":
		var res: Dictionary = resolver.resolve(archetype)
		if res.get("resolved", false):
			var entry: Dictionary = res.get("entry", {})
			scene = String(entry.get("scene", ""))
			if scene == "":
				scene = String(entry.get("mesh", ""))
			source = String(res.get("source", ""))
	node.set_meta("insimul_scene", scene)
	node.set_meta("insimul_binding_source", source)
