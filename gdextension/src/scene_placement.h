// scene_placement.h — the engine-neutral scene-generation PLACEMENT MATH core
// (US-GB2). std-only; the authority the cross-engine placement goldens pin.
//
// Given a World IR document (the golden export shape) and a resolved binding
// pack (the placeholder pack, US-GB2), this computes the deterministic
// PLACEMENT MANIFEST: the ordered set of nodes the @tool scene-generation
// pipeline must materialize — terrain chunks, roads, buildings, props,
// interiors and the navigation region — each carrying its stable
// InsimulEntityId, resolved asset, transform, and generated flag.
//
// Like binding_resolver.h / canonical_json.h this uses ONLY the C++ standard
// library so it host-tests under a plain clang toolchain (no godot-cpp, no
// libinsimul — see test/run_placement_tests.sh). The @tool GDScript twin
// (addons/insimul/editor/scene/insimul_scene_generator.gd) mirrors this exact
// math and emits the same manifest; the shared golden
// (addons/insimul/editor/scene/fixtures/golden-placement-manifest.json) pins
// BOTH so they can never diverge. This is the same host-vs-editor split used
// across the Godot leg and the cross-engine contract Unity/Unreal generate
// against too — the placement math is identical, only the node classes differ.
//
// Determinism contract: the manifest is a pure function of (IR, pack). Nodes
// are emitted in a canonical order (by entityId ascending) and every computed
// coordinate is quantized (see kCoordQuantum) so a 32-bit engine float and a
// 64-bit host double round to the same serialized value. Two runs — or two
// engines — therefore produce byte-identical manifests.

#ifndef INSIMUL_GODOT_SCENE_PLACEMENT_H
#define INSIMUL_GODOT_SCENE_PLACEMENT_H

#include "binding_resolver.h"
#include "json_value.h"

#include <string>
#include <vector>

namespace insimul {

// Coordinates are rounded to this quantum before serialization so float32 and
// float64 evaluations of the same placement agree byte-for-byte.
constexpr double kCoordQuantum = 0.001;

// Grid snap applied to building footprints (matches the runtime
// building_placement_system.gd GRID_SIZE).
constexpr double kGridSize = 1.0;

struct Vec3 {
	double x = 0.0;
	double y = 0.0;
	double z = 0.0;
};

// One node in the placement manifest.
struct PlacedNode {
	std::string entity_id;   // stable InsimulEntityId (the re-import match key)
	std::string archetype;   // taxonomy key resolved against the binding pack
	std::string kind;        // terrain_chunk | road | building | prop | interior | nav_region
	std::string scene;       // resolved res:// asset ("" when kind carries no asset)
	std::string binding_source; // which tier resolved it (for reporting)
	Vec3 position;
	double rotation_y = 0.0; // radians about +Y
	Vec3 scale{1.0, 1.0, 1.0};
	bool generated = true;   // every node this pipeline emits is generated
};

// Bilinear height lookup over a heightmap grid. `heights` is row-major
// (resolution x resolution) covering [0..size_x] x [0..size_z]; out-of-range
// world coords clamp to the edge. Returns 0 for a degenerate map.
double sample_terrain_height(const std::vector<double> &heights, int resolution,
		double size_x, double size_z, double world_x, double world_z);

// Round a coordinate to kCoordQuantum (banker-free nearest, ties away from 0).
double quantize_coord(double v);

struct PlacementResult {
	bool ok = false;
	std::string error;
	std::string seed;
	std::vector<PlacedNode> nodes; // canonical order (by entity_id ascending)
};

// Compute the placement manifest from a parsed World IR and a resolver whose
// tiers are already ordered (placeholder pack, plus any project/pack overrides).
PlacementResult compute_placement(const JsonValue &world_ir, const BindingResolver &resolver);

// Serialize a PlacementResult as the canonical placement-manifest JSON — the
// artifact compared against the shared golden. Key-sorted, minified,
// coordinate-quantized; byte-deterministic across runs and engines.
std::string serialize_placement_manifest(const PlacementResult &result);

// Convenience: parse `ir_json` + `pack_json`, build the resolver, compute, and
// serialize in one call. Returns the canonical manifest, or "" with `error` set.
std::string generate_placement_manifest(const std::string &ir_json,
		const std::string &pack_json, std::string &error);

} // namespace insimul

#endif // INSIMUL_GODOT_SCENE_PLACEMENT_H
