// scene_placement.cpp — implementation of the scene-generation placement math
// core (US-GB2). std-only; see scene_placement.h for the contract.

#include "scene_placement.h"

#include "canonical_json.h"

#include <algorithm>
#include <cmath>

namespace insimul {

namespace {

// Zone-based footprint scaling, mirroring the runtime
// building_placement_system.gd ZONE_SCALE table.
double zone_scale_for_role(const std::string &role) {
	if (role == "commercial") return 1.3;
	if (role == "downtown") return 1.4;
	if (role == "industrial") return 1.2;
	if (role == "outskirts") return 0.9;
	// residential and anything unknown are unscaled.
	return 1.0;
}

JsonValuePtr make_string(const std::string &s) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::String;
	v->string_value = s;
	return v;
}

JsonValuePtr make_bool(bool b) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Bool;
	v->bool_value = b;
	return v;
}

JsonValuePtr make_int(long long n) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Number;
	v->raw_number = std::to_string(n);
	v->number_value = static_cast<double>(n);
	return v;
}

// A number whose canonical form comes from the (already quantized) double.
JsonValuePtr make_number(double d) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Number;
	v->number_value = d;
	return v;
}

JsonValuePtr make_vec3(const Vec3 &p) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Object;
	v->object_items.push_back({"x", make_number(p.x)});
	v->object_items.push_back({"y", make_number(p.y)});
	v->object_items.push_back({"z", make_number(p.z)});
	return v;
}

double num_field(const JsonValue &obj, const std::string &key, double def) {
	const JsonValue *v = obj.find(key);
	return (v && v->is_number()) ? v->number_value : def;
}

// Read a {x,z} (and optional y) point object.
Vec3 read_point(const JsonValue &obj) {
	Vec3 p;
	p.x = num_field(obj, "x", 0.0);
	p.y = num_field(obj, "y", 0.0);
	p.z = num_field(obj, "z", 0.0);
	return p;
}

int ceil_div(double a, double b) {
	if (b <= 0.0) return 1;
	return static_cast<int>(std::ceil(a / b));
}

} // namespace

double quantize_coord(double v) {
	if (!std::isfinite(v)) return 0.0;
	// Round to kCoordQuantum by scaling with its exact integer inverse and
	// DIVIDING after the round — dividing keeps the result on the cleanest
	// nearby double (1.4 stays "1.4"), whereas multiplying by the inexact
	// 0.001 lexeme reintroduces float noise ("1.4000000000000001").
	const double inv = 1.0 / kCoordQuantum; // 1000.0, exactly representable
	double q = std::round(v * inv) / inv;
	// Normalize a signed zero to plain zero for a stable serialization.
	if (q == 0.0) return 0.0;
	return q;
}

double sample_terrain_height(const std::vector<double> &heights, int resolution,
		double size_x, double size_z, double world_x, double world_z) {
	if (resolution < 1 || heights.empty()) {
		return 0.0;
	}
	if (resolution == 1) {
		return heights[0];
	}
	if (size_x <= 0.0 || size_z <= 0.0) {
		return heights[0];
	}
	// World -> grid coordinates in [0, resolution-1], clamped to the edges.
	double gx = (world_x / size_x) * (resolution - 1);
	double gz = (world_z / size_z) * (resolution - 1);
	gx = std::min(std::max(gx, 0.0), static_cast<double>(resolution - 1));
	gz = std::min(std::max(gz, 0.0), static_cast<double>(resolution - 1));

	int x0 = static_cast<int>(std::floor(gx));
	int z0 = static_cast<int>(std::floor(gz));
	int x1 = std::min(x0 + 1, resolution - 1);
	int z1 = std::min(z0 + 1, resolution - 1);
	double fx = gx - x0;
	double fz = gz - z0;

	auto at = [&](int gxi, int gzi) -> double {
		std::size_t idx = static_cast<std::size_t>(gzi) * resolution + gxi;
		return idx < heights.size() ? heights[idx] : 0.0;
	};

	double h00 = at(x0, z0);
	double h10 = at(x1, z0);
	double h01 = at(x0, z1);
	double h11 = at(x1, z1);
	double top = h00 + (h10 - h00) * fx;
	double bot = h01 + (h11 - h01) * fx;
	return top + (bot - top) * fz;
}

namespace {

// Resolve an archetype through the chain and fill scene/source on the node.
void resolve_node_asset(const BindingResolver &resolver, PlacedNode &node) {
	if (node.archetype.empty()) {
		return;
	}
	ResolveResult r = resolver.resolve(node.archetype);
	if (r.resolved && r.entry) {
		node.scene = !r.entry->scene.empty() ? r.entry->scene : r.entry->mesh;
		node.binding_source = r.source_name;
	}
}

} // namespace

PlacementResult compute_placement(const JsonValue &world_ir, const BindingResolver &resolver) {
	PlacementResult result;
	if (!world_ir.is_object()) {
		result.error = "World IR root is not an object";
		return result;
	}

	const JsonValue *meta = world_ir.find("meta");
	if (meta && meta->is_object()) {
		result.seed = meta->get_string("seed", "");
	}

	const JsonValue *geography = world_ir.find("geography");
	const JsonValue *entities = world_ir.find("entities");

	// --- Terrain: heightmap + chunk grid ---------------------------------
	std::vector<double> heights;
	int resolution = 0;
	double size_x = 0.0, size_z = 0.0, chunk_size = 0.0;
	if (geography && geography->is_object()) {
		const JsonValue *terrain = geography->find("terrain");
		if (terrain && terrain->is_object()) {
			const JsonValue *size = terrain->find("size");
			if (size && size->is_object()) {
				size_x = num_field(*size, "x", 0.0);
				size_z = num_field(*size, "z", 0.0);
			}
			chunk_size = num_field(*terrain, "chunkSize", 0.0);
			const JsonValue *hm = terrain->find("heightmap");
			if (hm && hm->is_object()) {
				resolution = static_cast<int>(num_field(*hm, "resolution", 0.0));
				const JsonValue *harr = hm->find("heights");
				if (harr && harr->is_array()) {
					for (const auto &h : harr->array_items) {
						heights.push_back(h ? h->number_value : 0.0);
					}
				}
			}
		}
	}

	auto height_at = [&](double wx, double wz) -> double {
		return sample_terrain_height(heights, resolution, size_x, size_z, wx, wz);
	};

	if (size_x > 0.0 && size_z > 0.0 && chunk_size > 0.0) {
		int chunks_x = ceil_div(size_x, chunk_size);
		int chunks_z = ceil_div(size_z, chunk_size);
		for (int cz = 0; cz < chunks_z; ++cz) {
			for (int cx = 0; cx < chunks_x; ++cx) {
				PlacedNode node;
				node.entity_id = "terrain.chunk." + std::to_string(cx) + "_" + std::to_string(cz);
				node.archetype = "terrain";
				node.kind = "terrain_chunk";
				double centre_x = cx * chunk_size + chunk_size * 0.5;
				double centre_z = cz * chunk_size + chunk_size * 0.5;
				node.position = {centre_x, height_at(centre_x, centre_z), centre_z};
				resolve_node_asset(resolver, node);
				result.nodes.push_back(node);
			}
		}
	}

	// --- Roads ------------------------------------------------------------
	if (geography && geography->is_object()) {
		const JsonValue *roads = geography->find("roads");
		if (roads && roads->is_array()) {
			for (const auto &r : roads->array_items) {
				if (!r || !r->is_object()) continue;
				PlacedNode node;
				node.entity_id = r->get_string("id", "");
				node.archetype = r->get_string("archetype", "road");
				node.kind = "road";
				// Position at the centroid of the control points.
				const JsonValue *pts = r->find("points");
				double sx = 0.0, sz = 0.0;
				int count = 0;
				if (pts && pts->is_array()) {
					for (const auto &p : pts->array_items) {
						if (!p || !p->is_object()) continue;
						Vec3 pv = read_point(*p);
						sx += pv.x;
						sz += pv.z;
						++count;
					}
				}
				double cx = count > 0 ? sx / count : 0.0;
				double cz = count > 0 ? sz / count : 0.0;
				node.position = {cx, height_at(cx, cz), cz};
				resolve_node_asset(resolver, node);
				result.nodes.push_back(node);
			}
		}
	}

	// --- Buildings (+ interiors) -----------------------------------------
	if (entities && entities->is_object()) {
		const JsonValue *buildings = entities->find("buildings");
		if (buildings && buildings->is_array()) {
			for (const auto &b : buildings->array_items) {
				if (!b || !b->is_object()) continue;
				std::string role = b->get_string("role", "residential");
				PlacedNode node;
				node.entity_id = b->get_string("id", "");
				node.archetype = b->get_string("archetype", "building." + role);
				node.kind = "building";
				const JsonValue *pos = b->find("position");
				Vec3 p = (pos && pos->is_object()) ? read_point(*pos) : Vec3{};
				// Snap footprint to the placement grid, sample terrain height.
				double snapped_x = std::round(p.x / kGridSize) * kGridSize;
				double snapped_z = std::round(p.z / kGridSize) * kGridSize;
				node.position = {snapped_x, height_at(snapped_x, snapped_z), snapped_z};
				node.rotation_y = num_field(*b, "rotation", 0.0);
				double s = zone_scale_for_role(role);
				node.scale = {s, s, s};
				resolve_node_asset(resolver, node);
				result.nodes.push_back(node);

				// Interior as a SEPARATE scene at origin (door-warp convention).
				bool has_interior = false;
				const JsonValue *iv = b->find("interior");
				if (iv && iv->type == JsonType::Bool) {
					has_interior = iv->bool_value;
				}
				if (has_interior) {
					PlacedNode interior;
					interior.entity_id = node.entity_id + ".interior";
					interior.archetype = "interior." + role;
					interior.kind = "interior";
					interior.position = {0.0, 0.0, 0.0};
					resolve_node_asset(resolver, interior);
					result.nodes.push_back(interior);
				}
			}
		}

		// --- Props --------------------------------------------------------
		const JsonValue *props = entities->find("props");
		if (props && props->is_array()) {
			for (const auto &pr : props->array_items) {
				if (!pr || !pr->is_object()) continue;
				std::string kind = pr->get_string("kind", "generic");
				PlacedNode node;
				node.entity_id = pr->get_string("id", "");
				node.archetype = pr->get_string("archetype", "prop." + kind);
				node.kind = "prop";
				const JsonValue *pos = pr->find("position");
				Vec3 p = (pos && pos->is_object()) ? read_point(*pos) : Vec3{};
				node.position = {p.x, height_at(p.x, p.z), p.z};
				node.rotation_y = num_field(*pr, "rotation", 0.0);
				resolve_node_asset(resolver, node);
				result.nodes.push_back(node);
			}
		}
	}

	// --- Navigation region (single bake root, no asset) -------------------
	{
		PlacedNode nav;
		nav.entity_id = "nav.region";
		nav.kind = "nav_region";
		nav.position = {0.0, 0.0, 0.0};
		result.nodes.push_back(nav);
	}

	// Canonical order: stable sort by entity_id ascending.
	std::stable_sort(result.nodes.begin(), result.nodes.end(),
			[](const PlacedNode &a, const PlacedNode &b) { return a.entity_id < b.entity_id; });

	result.ok = true;
	return result;
}

std::string serialize_placement_manifest(const PlacementResult &result) {
	auto root = std::make_shared<JsonValue>();
	root->type = JsonType::Object;
	root->object_items.push_back({"manifestVersion", make_int(1)});
	root->object_items.push_back({"seed", make_string(result.seed)});
	root->object_items.push_back({"nodeCount", make_int(static_cast<long long>(result.nodes.size()))});

	auto nodes = std::make_shared<JsonValue>();
	nodes->type = JsonType::Array;
	for (const PlacedNode &n : result.nodes) {
		auto obj = std::make_shared<JsonValue>();
		obj->type = JsonType::Object;
		obj->object_items.push_back({"entityId", make_string(n.entity_id)});
		obj->object_items.push_back({"kind", make_string(n.kind)});
		obj->object_items.push_back({"archetype", make_string(n.archetype)});
		obj->object_items.push_back({"scene", make_string(n.scene)});
		obj->object_items.push_back({"bindingSource", make_string(n.binding_source)});
		obj->object_items.push_back({"generated", make_bool(n.generated)});
		Vec3 qp{quantize_coord(n.position.x), quantize_coord(n.position.y), quantize_coord(n.position.z)};
		obj->object_items.push_back({"position", make_vec3(qp)});
		obj->object_items.push_back({"rotationY", make_number(quantize_coord(n.rotation_y))});
		Vec3 qs{quantize_coord(n.scale.x), quantize_coord(n.scale.y), quantize_coord(n.scale.z)};
		obj->object_items.push_back({"scale", make_vec3(qs)});
		nodes->array_items.push_back(obj);
	}
	root->object_items.push_back({"nodes", nodes});

	return canonical_json_stringify(*root);
}

std::string generate_placement_manifest(const std::string &ir_json,
		const std::string &pack_json, std::string &error) {
	JsonParseResult ir = parse_json(ir_json);
	if (!ir.ok || !ir.root) {
		error = "IR parse error: " + ir.error;
		return "";
	}
	JsonParseResult pack = parse_json(pack_json);
	if (!pack.ok || !pack.root) {
		error = "pack parse error: " + pack.error;
		return "";
	}

	BindingResolver resolver;
	// The pack JSON is either a single pack object or a matrix { sources: [...] }.
	if (const JsonValue *sources = pack.root->find("sources"); sources && sources->is_array()) {
		std::string perr;
		if (!parse_resolver_matrix_sources(*sources, resolver, perr)) {
			error = "pack sources parse error: " + perr;
			return "";
		}
	} else {
		BindingSource src;
		std::string perr;
		if (!parse_binding_source(*pack.root, src, perr)) {
			error = "pack parse error: " + perr;
			return "";
		}
		resolver.add_source(std::move(src));
	}
	resolver.sort_sources_by_priority();

	PlacementResult placement = compute_placement(*ir.root, resolver);
	if (!placement.ok) {
		error = placement.error;
		return "";
	}
	return serialize_placement_manifest(placement);
}

} // namespace insimul
