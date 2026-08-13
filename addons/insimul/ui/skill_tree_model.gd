class_name InsimulSkillTreeModel
extends RefCounted
## Skill-tree view-model (US-GU2) — tiers, prerequisites, and what a spend buys.
##
## Backs the skill-tree panel, which the registry gates on the band-111 `skill`
## module: a world that does not activate Skills has no skill IR to draw, so the
## panel does not resolve at all (see addons/insimul/ui/panels.json).
##
## A skill node is { id, name, tier?, requires?: [id], cost?: int }. The model owns
## the three questions a tree UI asks:
##   - is this node UNLOCKED (already bought)?
##   - is it AVAILABLE (every prerequisite unlocked and the points are there)?
##   - what happens when the player clicks it?
## Everything else — colour per tier, node placement — is presentation.

var _order: Array[String] = []
var _nodes: Dictionary = {}          # id -> node Dictionary
var _unlocked: Dictionary = {}       # id -> true
var _points := 0


## Replace the whole node set, preserving the given order. Unlocks are kept only
## for ids the new set still has.
func set_nodes(nodes: Array) -> void:
	_order.clear()
	_nodes.clear()
	for n in nodes:
		var id := String((n as Dictionary).get("id", ""))
		if id.is_empty():
			continue
		if not _nodes.has(id):
			_order.append(id)
		_nodes[id] = (n as Dictionary).duplicate(true)
	for id in _unlocked.keys():
		if not _nodes.has(id):
			_unlocked.erase(id)


func nodes() -> Array:
	var out: Array = []
	for id in _order:
		out.append((_nodes[id] as Dictionary).duplicate(true))
	return out


func has_node(id: String) -> bool:
	return _nodes.has(id)


## Nodes on one tier, in declaration order — one row of the tree.
func nodes_in_tier(tier: int) -> Array:
	var out: Array = []
	for n in nodes():
		if int(n.get("tier", 0)) == tier:
			out.append(n)
	return out


## Every tier that has a node, ascending.
func tiers() -> Array:
	var seen := {}
	for id in _order:
		seen[int(_nodes[id].get("tier", 0))] = true
	var out := seen.keys()
	out.sort()
	return out


# ── Points ────────────────────────────────────────────────────────────────────

func points() -> int:
	return _points


func set_points(value: int) -> void:
	_points = maxi(0, value)


func grant_points(amount: int) -> void:
	set_points(_points + amount)


# ── Unlock state ──────────────────────────────────────────────────────────────

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func unlocked_ids() -> Array:
	var out: Array = []
	for id in _order:
		if _unlocked.has(id):
			out.append(id)
	return out


func cost_of(id: String) -> int:
	return int(_nodes.get(id, {}).get("cost", 1)) if _nodes.has(id) else 0


## The prerequisites of `id` that are not unlocked yet — why a node is still dim.
func missing_prerequisites(id: String) -> Array:
	var out: Array = []
	if not _nodes.has(id):
		return out
	for req in _nodes[id].get("requires", []):
		if not _unlocked.has(String(req)):
			out.append(String(req))
	return out


## True when `id` can be unlocked right now: it exists, it is not already
## unlocked, every prerequisite is, and the points are there.
func can_unlock(id: String) -> bool:
	if not _nodes.has(id) or _unlocked.has(id):
		return false
	if not missing_prerequisites(id).is_empty():
		return false
	return _points >= cost_of(id)


## Spend the points and unlock `id`. Returns false and changes nothing when
## [method can_unlock] says no — the panel shows the reason rather than the button.
func unlock(id: String) -> bool:
	if not can_unlock(id):
		return false
	_points -= cost_of(id)
	_unlocked[id] = true
	return true


## Restore a saved unlock set (ids the save already paid for). Points are not
## re-spent — this is a load, not a purchase.
func restore_unlocked(ids: Array) -> void:
	_unlocked.clear()
	for id in ids:
		if _nodes.has(String(id)):
			_unlocked[String(id)] = true


## What the panel draws per node: the node plus its three states.
func node_view(id: String) -> Dictionary:
	if not _nodes.has(id):
		return {}
	var view: Dictionary = (_nodes[id] as Dictionary).duplicate(true)
	view["unlocked"] = is_unlocked(id)
	view["available"] = can_unlock(id)
	view["missing"] = missing_prerequisites(id)
	return view
