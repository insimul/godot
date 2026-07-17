@tool
class_name InsimulReimport
extends RefCounted
## Re-import diff policy (US-GB3) — the @tool twin of the host diff core
## (packages/godot/gdextension/src/reimport_diff.cpp).
##
## When a world's IR is re-exported and the scene regenerated, this reconciles
## the freshly computed placement manifest against the scene tree already on disk
## WITHOUT clobbering a human's hand edits. The shared policy (identical across
## the Unity/Unreal legs):
##   - EntityId matching   — old/new nodes matched by `insimul_entity_id`.
##   - generated-only       — only `insimul_generated == true` nodes are touched.
##   - hand-edits untouched — a node the user set `insimul_generated = false` is
##                           preserved verbatim (present OR absent from the new
##                           manifest).
##   - Deprecated group     — a generated node the new manifest drops is moved
##                           under a "Deprecated" group node, never deleted.
##   - dry-run report       — compute_diff() is pure; apply_reimport() mutates.
##
## The classification here mirrors reimport_diff.cpp exactly; the shared golden
## (fixtures/golden-diff-report.json) pins BOTH via the host gate and the headless
## twin (reimport_test.gd). This runs only when a real `godot` binary is present
## (run_reimport_headless.sh); the host C++ gate holds the contract on a bare box.

## Name of the node the deprecated (dropped-but-generated) nodes are reparented
## under, and the group they join for the editor's Deprecated view.
const DEPRECATED_GROUP := "Deprecated"

# ---------------------------------------------------------------------------
# Diff classification (mirror of compute_reimport_diff)
# ---------------------------------------------------------------------------

## Classify every entityId across two manifest-node arrays (each element a
## Dictionary in the placement-manifest shape). Returns the dry-run report:
##   { reportVersion, added, updated, unchanged, skipped, deprecated, counts }
## Every id list is sorted ascending (deterministic). Pure — no side effects.
static func compute_diff(old_nodes: Array, new_nodes: Array) -> Dictionary:
	var old_by_id := {}
	for n in old_nodes:
		old_by_id[String(n.get("entityId", ""))] = n
	var new_by_id := {}
	for n in new_nodes:
		new_by_id[String(n.get("entityId", ""))] = n

	var added: Array = []
	var updated: Array = []
	var unchanged: Array = []
	var skipped: Array = []
	var deprecated: Array = []

	# New-manifest pass: added / skipped (hand edit) / updated / unchanged.
	for n in new_nodes:
		var id := String(n.get("entityId", ""))
		if not old_by_id.has(id):
			added.append(id)
			continue
		var o = old_by_id[id]
		if not bool(o.get("generated", false)):
			skipped.append(id)
			continue
		if _nodes_equivalent(o, n):
			unchanged.append(id)
		else:
			updated.append(id)

	# Old-manifest pass for ids absent from new: deprecated / skipped (hand edit).
	for o in old_nodes:
		var id := String(o.get("entityId", ""))
		if new_by_id.has(id):
			continue
		if bool(o.get("generated", false)):
			deprecated.append(id)
		else:
			skipped.append(id)

	added.sort()
	updated.sort()
	unchanged.sort()
	skipped.sort()
	deprecated.sort()

	return {
		"reportVersion": 1,
		"added": added,
		"updated": updated,
		"unchanged": unchanged,
		"skipped": skipped,
		"deprecated": deprecated,
		"counts": {
			"added": added.size(),
			"updated": updated.size(),
			"unchanged": unchanged.size(),
			"skipped": skipped.size(),
			"deprecated": deprecated.size(),
		},
	}


## True if two manifest nodes differ only in identity (same entityId) — i.e. an
## update would be a no-op. Mirrors placed_nodes_equivalent().
static func _nodes_equivalent(a: Dictionary, b: Dictionary) -> bool:
	for key in ["kind", "archetype", "scene", "bindingSource"]:
		if String(a.get(key, "")) != String(b.get(key, "")):
			return false
	if bool(a.get("generated", false)) != bool(b.get("generated", false)):
		return false
	if not _vec_equal(a.get("position", {}), b.get("position", {})):
		return false
	if not _vec_equal(a.get("scale", {}), b.get("scale", {})):
		return false
	var qa := InsimulSceneGenerator.quantize_coord(float(a.get("rotationY", 0.0)))
	var qb := InsimulSceneGenerator.quantize_coord(float(b.get("rotationY", 0.0)))
	return qa == qb


static func _vec_equal(a: Dictionary, b: Dictionary) -> bool:
	for axis in ["x", "y", "z"]:
		var qa := InsimulSceneGenerator.quantize_coord(float(a.get(axis, 0.0)))
		var qb := InsimulSceneGenerator.quantize_coord(float(b.get(axis, 0.0)))
		if qa != qb:
			return false
	return true


## Serialize a diff report to JSON (dry-run preview). Godot's JSON keeps
## insertion order; the canonical byte-parity check lives host-side in
## serialize_diff_report(). Sorting the top-level keys here keeps the preview
## stable for a human reading two runs side by side.
static func report_to_json(report: Dictionary) -> String:
	return JSON.stringify(report, "  ")


# ---------------------------------------------------------------------------
# Scene-tree reconciliation (apply the diff)
# ---------------------------------------------------------------------------

## Read the manifest-node array off a generated tree's direct children (nodes
## carrying `insimul_entity_id`). The Deprecated group node is skipped.
static func nodes_from_tree(root: Node) -> Array:
	var nodes: Array = []
	for child in root.get_children():
		if child.name == DEPRECATED_GROUP:
			continue
		if not child.has_meta("insimul_entity_id"):
			continue
		nodes.append(_record_of(child))
	return nodes


static func _record_of(node: Node) -> Dictionary:
	var rec := {
		"entityId": String(node.get_meta("insimul_entity_id", "")),
		"kind": String(node.get_meta("insimul_kind", "")),
		"archetype": String(node.get_meta("insimul_archetype", "")),
		"scene": String(node.get_meta("insimul_scene", "")),
		"bindingSource": String(node.get_meta("insimul_binding_source", "")),
		"generated": bool(node.get_meta("insimul_generated", false)),
	}
	if node is Node3D:
		var n := node as Node3D
		rec["position"] = {"x": n.position.x, "y": n.position.y, "z": n.position.z}
		rec["rotationY"] = n.rotation.y
		rec["scale"] = {"x": n.scale.x, "y": n.scale.y, "z": n.scale.z}
	return rec


## Reconcile `existing_root` (the on-disk scene, possibly hand-edited) against
## `fresh_root` (a freshly generated tree from the new IR — all generated). Both
## trees' direct children carry the standard insimul_* metadata. Returns the
## dry-run diff report; the tree is mutated per the policy:
##   - unchanged / skipped : existing node kept as-is.
##   - updated             : transform + metadata copied from the fresh node.
##   - added               : fresh node reparented into existing_root.
##   - deprecated          : existing node reparented under the Deprecated group.
static func apply_reimport(existing_root: Node, fresh_root: Node) -> Dictionary:
	var old_nodes := nodes_from_tree(existing_root)
	var new_nodes := nodes_from_tree(fresh_root)
	var report := compute_diff(old_nodes, new_nodes)

	var existing_by_id := _index_children(existing_root)
	var fresh_by_id := _index_children(fresh_root)

	# Updated: copy transform + metadata from the fresh node onto the existing one.
	for id in report["updated"]:
		var existing: Node = existing_by_id.get(id, null)
		var fresh: Node = fresh_by_id.get(id, null)
		if existing != null and fresh != null:
			_copy_generated_state(fresh, existing)

	# Added: move the fresh node into the existing tree.
	for id in report["added"]:
		var fresh: Node = fresh_by_id.get(id, null)
		if fresh != null:
			fresh.get_parent().remove_child(fresh)
			existing_root.add_child(fresh)

	# Deprecated: reparent under the Deprecated group (never delete).
	for id in report["deprecated"]:
		var existing: Node = existing_by_id.get(id, null)
		if existing != null:
			var group := _ensure_deprecated_group(existing_root)
			existing.get_parent().remove_child(existing)
			group.add_child(existing)
			existing.add_to_group("insimul_deprecated")

	return report


static func _index_children(root: Node) -> Dictionary:
	var out := {}
	for child in root.get_children():
		if child.name == DEPRECATED_GROUP:
			continue
		if child.has_meta("insimul_entity_id"):
			out[String(child.get_meta("insimul_entity_id"))] = child
	return out


static func _ensure_deprecated_group(root: Node) -> Node:
	for child in root.get_children():
		if child.name == DEPRECATED_GROUP:
			return child
	var group := Node3D.new()
	group.name = DEPRECATED_GROUP
	root.add_child(group)
	return group


## Copy the generated transform + binding metadata from `src` onto `dst` (an
## update re-applies only the generated state; a hand edit never reaches here).
static func _copy_generated_state(src: Node, dst: Node) -> void:
	if src is Node3D and dst is Node3D:
		var s := src as Node3D
		var d := dst as Node3D
		d.position = s.position
		d.rotation = s.rotation
		d.scale = s.scale
	for key in ["insimul_kind", "insimul_archetype", "insimul_scene", "insimul_binding_source", "insimul_generated"]:
		if src.has_meta(key):
			dst.set_meta(key, src.get_meta(key))
