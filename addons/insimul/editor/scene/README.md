# Scene generation pipeline (US-GB2)

The editor-time (`@tool`) scene-generation pipeline: given a World IR export and
the Asset Binding Layer resolver (US-GB1), it materializes the generated Godot
scene tree — terrain chunks, roads, buildings, props, interiors and a navigation
bake root — and stamps every generated node with its stable InsimulEntityId +
`insimul_generated` flag (the re-import diff keys, US-GB3).

## Host-vs-editor split (the load-bearing pattern)

The **placement math** is the cross-engine contract, so it lives in a
dependency-free C++ core host-tested on a bare box; the **scene materialization**
is the GDScript twin gated on a real Godot binary:

- `gdextension/src/scene_placement.{h,cpp}` — the std-only placement core.
  `compute_placement(ir, resolver)` → `serialize_placement_manifest(...)` emits
  the canonical **placement manifest** (key-sorted, minified, coordinate-
  quantized). Host gate: `gdextension/test/run_placement_tests.sh` (golden-match
  + placeholder-coverage + determinism). This is the authority.
- `insimul_scene_generator.gd` — the `@tool` twin. `generate(ir, resolver)`
  builds the real node tree (MeshInstance3D terrain chunks + HeightMapShape3D
  collision, Path3D roads, resolved PackedScene placement, separate interior
  scene roots, NavigationRegion3D); `manifest_from_tree(root, seed)` reads the
  manifest back off the generated nodes' metadata. Headless gate:
  `run_scene_generator_headless.sh` (SKIPs with exit 0 when no `godot` binary is
  present — the host gate holds the contract there).
- `insimul_placeholder_pack.gd` — the procedural placeholder pack: primitive
  meshes via `SurfaceTool` + taxonomy-labeled `StandardMaterial3D` materials, and
  the `insimul-binding-pack` table (`build_pack_dict()`) that must stay
  byte-compatible with `fixtures/placeholder-pack.json`.

A single set of shared fixtures drives BOTH implementations so they can never
diverge; the same manifest shape is the contract Unity/Unreal generate against.

## Fixtures

- `fixtures/golden-ir.json` — the shared golden World IR. Exercises every
  taxonomy the placeholder pack must cover (terrain heightmap + chunks, roads,
  buildings with zone roles + an interior, props).
- `fixtures/placeholder-pack.json` — the placeholder `insimul-binding-pack`
  (priority 0 fallback tier), one taxonomy-labeled entry per golden archetype
  plus a `*` catch-all. `scene` = instanced placeholder; `mesh` = bare primitive.
- `fixtures/golden-placement-manifest.json` — the expected canonical manifest.
  **Regenerate** with `bash gdextension/test/run_placement_tests.sh dump` (never
  by hand) after any change to the placement math or the golden IR, then commit.

## Placement manifest shape

```json
{
  "manifestVersion": 1,
  "seed": "<meta.seed>",
  "nodeCount": <int>,
  "nodes": [
    {
      "entityId": "<stable InsimulEntityId>",
      "kind": "terrain_chunk | road | building | prop | interior | nav_region",
      "archetype": "<taxonomy key resolved against the binding pack>",
      "scene": "<resolved res:// asset ('' for nav_region)>",
      "bindingSource": "<tier name that resolved it>",
      "generated": true,
      "position": { "x": <n>, "y": <n>, "z": <n> },
      "rotationY": <radians>,
      "scale": { "x": <n>, "y": <n>, "z": <n> }
    }
  ]
}
```

Nodes are emitted in canonical order (by `entityId` ascending) and every
coordinate is rounded to `kCoordQuantum` (0.001) so a 32-bit engine float and a
64-bit host double serialize identically — the determinism + cross-engine parity
guarantee.

## Placement math summary

- **Terrain**: chunk grid = `ceil(size / chunkSize)` per axis; each chunk centered
  in its cell, `y` = bilinear `sample_terrain_height` over the heightmap.
- **Roads**: positioned at the centroid of their control points, `y` sampled.
- **Buildings**: footprint snapped to the 1.0 grid, `y` sampled, `rotationY` from
  the IR, uniform scale from the zone role table (downtown 1.4, commercial 1.3,
  industrial 1.2, outskirts 0.9, else 1.0). `interior: true` emits a SEPARATE
  interior node at the origin (the door-warp convention).
- **Props**: placed at their IR position (no grid snap), `y` sampled.
- **Navigation**: one `nav_region` node at the origin, no asset.
