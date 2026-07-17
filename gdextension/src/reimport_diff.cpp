// reimport_diff.cpp — implementation of the re-import diff policy core (US-GB3).
// std-only; see reimport_diff.h for the contract.

#include "reimport_diff.h"

#include "canonical_json.h"

#include <algorithm>
#include <map>

namespace insimul {

namespace {

JsonValuePtr make_string(const std::string &s) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::String;
	v->string_value = s;
	return v;
}

JsonValuePtr make_int(long long n) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Number;
	v->raw_number = std::to_string(n);
	v->number_value = static_cast<double>(n);
	return v;
}

JsonValuePtr make_id_array(const std::vector<std::string> &ids) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Array;
	for (const std::string &id : ids) {
		v->array_items.push_back(make_string(id));
	}
	return v;
}

// Read a {x,y,z} vector object (missing axes default to 0).
Vec3 read_vec3(const JsonValue *obj) {
	Vec3 p;
	if (obj && obj->is_object()) {
		const JsonValue *x = obj->find("x");
		const JsonValue *y = obj->find("y");
		const JsonValue *z = obj->find("z");
		p.x = (x && x->is_number()) ? x->number_value : 0.0;
		p.y = (y && y->is_number()) ? y->number_value : 0.0;
		p.z = (z && z->is_number()) ? z->number_value : 0.0;
	}
	return p;
}

bool vec3_equal_quantized(const Vec3 &a, const Vec3 &b) {
	return quantize_coord(a.x) == quantize_coord(b.x) &&
			quantize_coord(a.y) == quantize_coord(b.y) &&
			quantize_coord(a.z) == quantize_coord(b.z);
}

} // namespace

bool placed_nodes_equivalent(const PlacedNode &a, const PlacedNode &b) {
	// entity_id is the match key, not part of the equivalence test.
	if (a.kind != b.kind) return false;
	if (a.archetype != b.archetype) return false;
	if (a.scene != b.scene) return false;
	if (a.binding_source != b.binding_source) return false;
	if (a.generated != b.generated) return false;
	if (!vec3_equal_quantized(a.position, b.position)) return false;
	if (!vec3_equal_quantized(a.scale, b.scale)) return false;
	if (quantize_coord(a.rotation_y) != quantize_coord(b.rotation_y)) return false;
	return true;
}

DiffReport compute_reimport_diff(const std::vector<PlacedNode> &old_nodes,
		const std::vector<PlacedNode> &new_nodes) {
	DiffReport report;

	// Index old nodes by entityId (last wins on a duplicate id — degenerate).
	std::map<std::string, const PlacedNode *> old_by_id;
	for (const PlacedNode &n : old_nodes) {
		old_by_id[n.entity_id] = &n;
	}
	std::map<std::string, const PlacedNode *> new_by_id;
	for (const PlacedNode &n : new_nodes) {
		new_by_id[n.entity_id] = &n;
	}

	// Walk the NEW manifest: added / skipped-handedit / updated / unchanged.
	for (const PlacedNode &n : new_nodes) {
		auto it = old_by_id.find(n.entity_id);
		if (it == old_by_id.end()) {
			report.added.push_back(n.entity_id);
			continue;
		}
		const PlacedNode &o = *it->second;
		if (!o.generated) {
			// Hand edit: preserve verbatim, even though the new manifest lists it.
			report.skipped.push_back(n.entity_id);
			continue;
		}
		if (placed_nodes_equivalent(o, n)) {
			report.unchanged.push_back(n.entity_id);
		} else {
			report.updated.push_back(n.entity_id);
		}
	}

	// Walk the OLD manifest for ids absent from NEW: deprecated (generated) or
	// skipped (hand edit kept as-is).
	for (const PlacedNode &o : old_nodes) {
		if (new_by_id.count(o.entity_id)) {
			continue; // handled in the new-manifest pass above
		}
		if (o.generated) {
			report.deprecated.push_back(o.entity_id);
		} else {
			report.skipped.push_back(o.entity_id);
		}
	}

	// Canonical ordering — every id list ascending.
	std::sort(report.added.begin(), report.added.end());
	std::sort(report.updated.begin(), report.updated.end());
	std::sort(report.unchanged.begin(), report.unchanged.end());
	std::sort(report.skipped.begin(), report.skipped.end());
	std::sort(report.deprecated.begin(), report.deprecated.end());
	return report;
}

bool parse_manifest_nodes(const JsonValue &manifest, std::vector<PlacedNode> &out,
		std::string &error) {
	out.clear();
	if (!manifest.is_object()) {
		error = "manifest is not an object";
		return false;
	}
	const JsonValue *nodes = manifest.find("nodes");
	if (!nodes || !nodes->is_array()) {
		error = "manifest.nodes missing or not an array";
		return false;
	}
	for (const JsonValuePtr &item : nodes->array_items) {
		if (!item || !item->is_object()) {
			error = "manifest.nodes entry is not an object";
			return false;
		}
		PlacedNode n;
		n.entity_id = item->get_string("entityId", "");
		if (n.entity_id.empty()) {
			error = "manifest node missing entityId";
			return false;
		}
		n.kind = item->get_string("kind", "");
		n.archetype = item->get_string("archetype", "");
		n.scene = item->get_string("scene", "");
		n.binding_source = item->get_string("bindingSource", "");
		n.generated = item->get_bool("generated", false);
		n.position = read_vec3(item->find("position"));
		{
			const JsonValue *ry = item->find("rotationY");
			n.rotation_y = (ry && ry->is_number()) ? ry->number_value : 0.0;
		}
		{
			const JsonValue *sc = item->find("scale");
			n.scale = sc ? read_vec3(sc) : Vec3{1.0, 1.0, 1.0};
		}
		out.push_back(std::move(n));
	}
	return true;
}

std::string serialize_diff_report(const DiffReport &report) {
	auto root = std::make_shared<JsonValue>();
	root->type = JsonType::Object;

	root->object_items.push_back({"reportVersion", make_int(1)});
	root->object_items.push_back({"added", make_id_array(report.added)});
	root->object_items.push_back({"updated", make_id_array(report.updated)});
	root->object_items.push_back({"unchanged", make_id_array(report.unchanged)});
	root->object_items.push_back({"skipped", make_id_array(report.skipped)});
	root->object_items.push_back({"deprecated", make_id_array(report.deprecated)});

	auto counts = std::make_shared<JsonValue>();
	counts->type = JsonType::Object;
	counts->object_items.push_back({"added", make_int((long long)report.added.size())});
	counts->object_items.push_back({"updated", make_int((long long)report.updated.size())});
	counts->object_items.push_back({"unchanged", make_int((long long)report.unchanged.size())});
	counts->object_items.push_back({"skipped", make_int((long long)report.skipped.size())});
	counts->object_items.push_back({"deprecated", make_int((long long)report.deprecated.size())});
	root->object_items.push_back({"counts", counts});

	return canonical_json_stringify(*root);
}

std::string generate_reimport_report(const std::string &old_manifest_json,
		const std::string &new_manifest_json, std::string &error) {
	JsonParseResult old_p = parse_json(old_manifest_json);
	if (!old_p.ok || !old_p.root) {
		error = "old manifest parse: " + old_p.error;
		return "";
	}
	JsonParseResult new_p = parse_json(new_manifest_json);
	if (!new_p.ok || !new_p.root) {
		error = "new manifest parse: " + new_p.error;
		return "";
	}
	std::vector<PlacedNode> old_nodes, new_nodes;
	if (!parse_manifest_nodes(*old_p.root, old_nodes, error)) {
		error = "old manifest: " + error;
		return "";
	}
	if (!parse_manifest_nodes(*new_p.root, new_nodes, error)) {
		error = "new manifest: " + error;
		return "";
	}
	DiffReport report = compute_reimport_diff(old_nodes, new_nodes);
	return serialize_diff_report(report);
}

} // namespace insimul
