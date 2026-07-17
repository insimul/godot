@tool
class_name InsimulPlaceholderPack
extends RefCounted
## Procedural placeholder pack builder (US-GB2).
##
## Generates the taxonomy-labeled placeholder assets the scene-generation
## pipeline binds to before any real art exists: primitive meshes built with
## SurfaceTool and flat, taxonomy-colored StandardMaterial3D materials, plus the
## `insimul-binding-pack` table (the US-GB1 pack contract) mapping every golden
## taxonomy key to its placeholder resource path.
##
## The emitted table is byte-compatible with fixtures/placeholder-pack.json (the
## shared coverage fixture); `build_pack_dict()` is the single source both the
## editor and the coverage test consult. Runs only under a real `godot` binary
## (the SurfaceTool/StandardMaterial3D calls need the engine); the committed
## fixture is what the host coverage gate checks on a bare box.

const PLACEHOLDER_DIR := "res://addons/insimul/placeholders"

## Taxonomy key -> { path, color, primitive }. `primitive` picks the mesh shape;
## `color` is the taxonomy-labeled material tint. Descendant/wildcard keys
## (`building`, `prop`, `*`) cover any archetype not spelled out explicitly.
const TAXONOMY := {
	"*": { "path": "placeholder_cube.tscn", "color": Color(0.6, 0.6, 0.6), "primitive": "box" },
	"terrain": { "path": "terrain_chunk.tres", "color": Color(0.4, 0.55, 0.3), "primitive": "plane" },
	"road": { "path": "road_strip.tres", "color": Color(0.25, 0.25, 0.25), "primitive": "box" },
	"building": { "path": "building_generic.tscn", "color": Color(0.7, 0.6, 0.5), "primitive": "box" },
	"building.residential": { "path": "building_residential.tscn", "color": Color(0.8, 0.7, 0.55), "primitive": "box" },
	"building.commercial": { "path": "building_commercial.tscn", "color": Color(0.55, 0.65, 0.8), "primitive": "box" },
	"building.downtown": { "path": "building_downtown.tscn", "color": Color(0.5, 0.55, 0.7), "primitive": "box" },
	"building.industrial": { "path": "building_industrial.tscn", "color": Color(0.6, 0.55, 0.5), "primitive": "box" },
	"building.outskirts": { "path": "building_outskirts.tscn", "color": Color(0.65, 0.7, 0.55), "primitive": "box" },
	"interior": { "path": "interior_generic.tscn", "color": Color(0.7, 0.7, 0.75), "primitive": "box" },
	"prop": { "path": "prop_generic.tscn", "color": Color(0.7, 0.5, 0.4), "primitive": "box" },
	"prop.tree": { "path": "prop_tree.tscn", "color": Color(0.2, 0.5, 0.25), "primitive": "cylinder" },
	"prop.lamp": { "path": "prop_lamp.tscn", "color": Color(0.85, 0.8, 0.4), "primitive": "cylinder" },
}


## Build the `insimul-binding-pack` table (priority 0, the fallback tier). Its
## entries carry `scene` for instanced placeholders and `mesh` for the bare
## primitive resources (terrain/road) — matching fixtures/placeholder-pack.json.
func build_pack_dict() -> Dictionary:
	var entries: Array = []
	var keys: Array = TAXONOMY.keys()
	keys.sort()
	for key in keys:
		var meta: Dictionary = TAXONOMY[key]
		var path := "%s/%s" % [PLACEHOLDER_DIR, meta["path"]]
		var entry := { "key": key }
		if String(meta["path"]).ends_with(".tres"):
			entry["mesh"] = path
		else:
			entry["scene"] = path
		entries.append(entry)
	return {
		"format": "insimul-binding-pack",
		"version": 1,
		"name": "insimul-placeholder",
		"priority": 0,
		"entries": entries,
	}


## Build the placeholder pack as an InsimulBindingTable ready to add as the
## resolver's lowest-priority tier.
func build_table() -> InsimulBindingTable:
	var table := InsimulBindingTable.new()
	table.from_pack_dict(build_pack_dict())
	return table


## Build a taxonomy-labeled primitive mesh via SurfaceTool. Every generated
## placeholder shares this so the whole pack reads as one flat-shaded system.
func build_primitive_mesh(primitive: String, color: Color) -> Mesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	match primitive:
		"plane":
			_emit_quad(st, 1.0)
		"cylinder":
			_emit_box(st, Vector3(0.3, 1.0, 0.3))
		_:
			_emit_box(st, Vector3(1.0, 1.0, 1.0))
	st.generate_normals()
	return st.commit()


func _emit_quad(st: SurfaceTool, s: float) -> void:
	var h := s * 0.5
	var a := Vector3(-h, 0.0, -h)
	var b := Vector3(h, 0.0, -h)
	var c := Vector3(h, 0.0, h)
	var d := Vector3(-h, 0.0, h)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


func _emit_box(st: SurfaceTool, dims: Vector3) -> void:
	# A unit box centered at origin; six faces as two triangles each.
	var h := dims * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
		[1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		st.add_vertex(corners[f[0]])
		st.add_vertex(corners[f[1]])
		st.add_vertex(corners[f[2]])
		st.add_vertex(corners[f[0]])
		st.add_vertex(corners[f[2]])
		st.add_vertex(corners[f[3]])
