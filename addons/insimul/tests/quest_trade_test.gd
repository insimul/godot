# quest_trade_test.gd — the Godot headless leg of the default-UI US-GU2 gate.
#
# Runs the shared, engine-neutral quest + trade matrices
# (packages/core/conformance/ui/{quest-journal-cases,trade-cases}.json) against the
# pure GDScript view-models — InsimulQuestJournalModel + InsimulTradeModel — plus
# the STATE-LOCATION INVARIANT (the trade model keeps no private store: reads return
# the live currentState arrays, and buy/sell/take conserve gold + item census). No
# GDExtension is needed (all pure GDScript), so this runs on any godot binary:
#
#   godot --headless -s addons/insimul/tests/quest_trade_test.gd -- --ui /abs/ui
#
# It SKIPS cleanly (exit 0) only when no godot binary is available (the Ralph
# harness) — the structural lint covers the .gd files there. Mirrors ui_registry_test.gd.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var ui_dir := _resolve_ui_dir()
	print("[insimul-ui2] corpus: %s" % ui_dir)

	_test_quest_cases(ui_dir)
	_test_trade_cases(ui_dir)
	_test_state_location_invariant()
	_test_quest_system_binding()
	_test_shared_models_notify()
	_test_map_model()
	_test_skill_tree_model()
	_test_document_pagination()
	_test_radial_selection()
	_test_quickbar()
	_test_notice_board()

	print("-----------------------------------------------------------")
	print("[insimul-ui2] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ── AC: quest journal / tracker / offer shared cases ─────────────────────────
func _test_quest_cases(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("quest-journal-cases.json"))
	if doc.is_empty():
		_report("read quest-journal-cases.json", false, "empty/parse error")
		return
	for case in doc.get("cases", []):
		var name: String = case.get("name", "?")
		var model := InsimulQuestJournalModel.new(int(case.get("max_tracked", 3)))
		model.set_quests(case.get("quests", []))
		for step in case.get("steps", []):
			var op := String(step.get("op", ""))
			var arg := String(step.get("arg", ""))
			var ok := true
			var checked_ok := false
			match op:
				"set_filter":
					model.set_filter(arg)
				"accept":
					ok = model.accept(arg); checked_ok = true
				"decline":
					ok = model.decline(arg); checked_ok = true
				"complete":
					ok = model.complete(arg); checked_ok = true
				"track":
					ok = model.track(arg); checked_ok = true
				"untrack":
					ok = model.untrack(arg); checked_ok = true
				"upsert":
					model.upsert(step.get("entry", {}))
				_:
					_report("quest[%s] unknown op %s" % [name, op], false, "")
			if checked_ok and step.has("expected_ok"):
				_report("quest[%s].%s ok" % [name, op], ok == bool(step.get("expected_ok")),
					"expected %s" % str(step.get("expected_ok")))
			if step.has("expected_filtered_ids"):
				_report("quest[%s].%s filtered" % [name, op],
					model.filtered_ids() == _str_array(step.get("expected_filtered_ids")),
					"got %s" % str(model.filtered_ids()))
			if step.has("expected_tracked_ids"):
				_report("quest[%s].%s tracked" % [name, op],
					model.tracked_ids() == _str_array(step.get("expected_tracked_ids")),
					"got %s" % str(model.tracked_ids()))
		_report("quest[%s] counts" % name, _deep_eq(model.counts(), case.get("expected_counts", {})),
			"got %s" % str(model.counts()))


# ── AC: trade inventory / container / merchant shared cases ───────────────────
func _test_trade_cases(ui_dir: String) -> void:
	var doc := _load_json(ui_dir.path_join("trade-cases.json"))
	if doc.is_empty():
		_report("read trade-cases.json", false, "empty/parse error")
		return
	for case in doc.get("cases", []):
		var name: String = case.get("name", "?")
		var state: Dictionary = (case.get("state", {}) as Dictionary).duplicate(true)
		var model := InsimulTradeModel.new(state)
		var op: Dictionary = case.get("op", {})
		var expected: Dictionary = case.get("expected", {})
		var result := _run_trade_op(model, op)

		_report("trade[%s] ok" % name, result.get("ok", false) == bool(expected.get("ok", false)),
			"got %s" % str(result))
		if expected.has("reason"):
			_report("trade[%s] reason" % name, String(result.get("reason", "")) == String(expected.get("reason")),
				"got '%s'" % result.get("reason", ""))
		if expected.has("moved"):
			_report("trade[%s] moved" % name, int(result.get("moved", 0)) == int(expected.get("moved")),
				"got %d" % int(result.get("moved", 0)))
		if expected.has("player_gold"):
			_report("trade[%s] player_gold" % name, model.player_gold() == int(expected.get("player_gold")),
				"got %d" % model.player_gold())
		if expected.has("player_items"):
			_report("trade[%s] player_items" % name, _deep_eq(_census(model.player_items()), expected.get("player_items")),
				"got %s" % str(_census(model.player_items())))
		if op.has("container") and expected.has("container_items"):
			_report("trade[%s] container_items" % name,
				_deep_eq(_census(model.container_items(String(op.get("container")))), expected.get("container_items")),
				"got %s" % str(_census(model.container_items(String(op.get("container"))))))
		if op.has("merchant"):
			var mid := String(op.get("merchant"))
			if expected.has("merchant_gold"):
				_report("trade[%s] merchant_gold" % name, model.merchant_gold(mid) == int(expected.get("merchant_gold")),
					"got %d" % model.merchant_gold(mid))
			if expected.has("merchant_items"):
				_report("trade[%s] merchant_items" % name,
					_deep_eq(_census(model.merchant_items(mid)), expected.get("merchant_items")),
					"got %s" % str(_census(model.merchant_items(mid))))


# ── AC: state-location invariant (no private store; conservation) ─────────────
func _test_state_location_invariant() -> void:
	# Reads return the live currentState arrays (identity, not a copy). Arrays are
	# reference types in GDScript, so appending to the returned array must mutate the
	# save's array — proving there is no private store.
	var state := _fresh_state()
	var model := InsimulTradeModel.new(state)
	model.player_items().append({"itemId": "_probe", "quantity": 1})
	_report("invariant reads player.inventory by reference",
		_count(state["player"]["inventory"], "_probe") == 1, "returned a copy, not the live array")
	model.container_items("chest1").append({"itemId": "_probe", "quantity": 1})
	_report("invariant reads container.items by reference",
		_count(state["containers"]["containers"]["chest1"]["items"], "_probe") == 1, "returned a copy")

	# Two models over two states never share a store.
	var a := _fresh_state()
	var b := _fresh_state()
	InsimulTradeModel.new(a).buy("shop1", "sword", 1)
	_report("invariant no static store (b untouched)", int(b["player"]["gold"]) == 100, "b gold changed")

	# Merchant trade conserves gold.
	var s := _fresh_state()
	var before_gold := int(s["player"]["gold"]) + int(s["npcs"]["merchantStates"]["shop1"]["goldReserve"])
	var tm := InsimulTradeModel.new(s)
	tm.buy("shop1", "sword", 1)
	var after_gold := int(s["player"]["gold"]) + int(s["npcs"]["merchantStates"]["shop1"]["goldReserve"])
	_report("invariant gold conserved on buy", after_gold == before_gold, "%d -> %d" % [before_gold, after_gold])

	# Container take conserves the item census.
	var s2 := _fresh_state()
	var tm2 := InsimulTradeModel.new(s2)
	var before_potions := _count(s2["player"]["inventory"], "potion") + _count(s2["containers"]["containers"]["chest1"]["items"], "potion")
	tm2.take_from_container("chest1", "potion", 3)
	var after_potions := _count(s2["player"]["inventory"], "potion") + _count(s2["containers"]["containers"]["chest1"]["items"], "potion")
	_report("invariant item census conserved on take", after_potions == before_potions,
		"%d -> %d" % [before_potions, after_potions])


func _fresh_state() -> Dictionary:
	return {
		"player": {"gold": 100, "inventory": [{"itemId": "gem", "quantity": 2, "value": 30}]},
		"containers": {"containers": {"chest1": {"items": [{"itemId": "potion", "quantity": 4, "value": 10}]}}},
		"npcs": {"merchantStates": {"shop1": {"goldReserve": 200, "items": [{"itemId": "sword", "quantity": 1, "value": 50}]}}},
	}


# ── AC: the panels run on the REAL quest system (signals, radiant arrivals) ────

## The live quest system's contract, as the journal model sees it: three signals
## with InsimulQuestSystem's exact signatures plus the projection accessors. The
## binding is duck-typed on purpose — addons/insimul/ui/ may not name a class that
## reaches into the GDExtension — so this stub IS the interface under test.
class StubQuestSystem extends RefCounted:
	signal quest_accepted(quest_id: String)
	signal quest_completed(quest_id: String)
	signal objective_completed(quest_id: String, objective_id: String)
	signal quest_offered(quest_id: String, tick: int)

	var projections: Dictionary = {}
	var active: Array = []
	var completed: Array = []

	func get_all_quest_ids() -> Array:
		return projections.keys()

	func get_projection(quest_id: String) -> Dictionary:
		return (projections.get(quest_id, {}) as Dictionary).duplicate(true)

	func is_quest_active(quest_id: String) -> bool:
		return active.has(quest_id)

	func is_quest_completed(quest_id: String) -> bool:
		return completed.has(quest_id)

	## What InsimulQuestSystem.run_radiant_tick() does at the end of a tick.
	func offer(quest_id: String, title: String, tick: int) -> void:
		projections[quest_id] = {"id": quest_id, "title": title, "difficulty": "medium"}
		quest_offered.emit(quest_id, tick)


func _test_quest_system_binding() -> void:
	var system := StubQuestSystem.new()
	system.projections["q_seed"] = {"id": "q_seed", "title": "The Seeded Quest"}
	system.active.append("q_seed")

	var model := InsimulQuestJournalModel.new(3)
	var connected := model.bind_quest_system(system)
	_report("binding connects the three quest signals", connected.size() == 3,
		"connected %s" % str(connected))
	_report("binding hydrates what the system already holds",
		String(model.get_quest("q_seed").get("status", "")) == "active",
		"got %s" % str(model.get_quest("q_seed")))

	# A radiant arrival: run_radiant_tick emits quest_offered, and the journal shows
	# it under Available with the system's own projection — nothing polled.
	system.offer("q_radiant", "Bandits on the North Road", 42)
	var radiant := model.get_quest("q_radiant")
	_report("radiant arrival lands in the journal", not radiant.is_empty(), "no such quest")
	_report("radiant arrival is available", String(radiant.get("status", "")) == "available",
		"status %s" % String(radiant.get("status", "")))
	_report("radiant arrival carries the system projection",
		String(radiant.get("title", "")) == "Bandits on the North Road",
		"title %s" % String(radiant.get("title", "")))
	model.set_filter("available")
	_report("radiant arrival shows under the Available tab",
		_str_array(model.filtered_ids()) == ["q_radiant"], "got %s" % str(model.filtered_ids()))

	# An accept made by the SYSTEM (a giver NPC, a script) reaches the journal.
	system.active.append("q_radiant")
	system.quest_accepted.emit("q_radiant")
	_report("system accept reaches the journal",
		String(model.get_quest("q_radiant").get("status", "")) == "active",
		"got %s" % str(model.get_quest("q_radiant")))

	# A completion untracks, exactly as complete() does.
	model.track("q_radiant")
	system.completed.append("q_radiant")
	system.quest_completed.emit("q_radiant")
	_report("system completion reaches the journal",
		String(model.get_quest("q_radiant").get("status", "")) == "completed",
		"got %s" % str(model.get_quest("q_radiant")))
	_report("system completion untracks the quest", not model.is_tracked("q_radiant"), "still tracked")

	# Binding twice must not double-connect (a panel rebinding on world reload).
	var again := model.bind_quest_system(system)
	_report("rebinding connects nothing twice", again.size() == 0, "reconnected %s" % str(again))

	# A source with none of the signals is not an error — it is a system that
	# predates them, and the journal simply stays manual.
	_report("binding a non-system is a no-op",
		InsimulQuestJournalModel.new().bind_quest_system(RefCounted.new()).size() == 0,
		"connected something")


# ── AC: the panels SHARE a model, and the model says when to redraw ───────────
func _test_shared_models_notify() -> void:
	var state := _fresh_state()
	var trade := InsimulTradeModel.new(state)
	var counter := SignalCounter.new()
	trade.state_changed.connect(counter.bump)
	trade.take_from_container("chest1", "potion", 1)
	_report("a successful take notifies", counter.count == 1, "count %d" % counter.count)
	trade.buy("shop1", "sword", 99)
	_report("a rejected op notifies nothing", counter.count == 1, "count %d" % counter.count)

	# Two panels over ONE model see one state: the take above is already in the
	# inventory panel's reading, because there is no private store to be stale.
	var inventory := InsimulInventoryPanel.new()
	var container := InsimulContainerPanel.new()
	inventory.set_model(trade)
	container.set_model(trade)
	_report("the shared model is the same object", inventory.model() == container.model(), "different models")
	_report("the shared model reads the live state",
		_count(inventory.model().player_items(), "potion") == 1,
		"got %s" % str(_census(inventory.model().player_items())))
	inventory.free()
	container.free()

	var journal := InsimulQuestJournalModel.new()
	var quest_counter := SignalCounter.new()
	journal.changed.connect(quest_counter.bump)
	journal.upsert({"id": "q1", "title": "A", "status": "available"})
	journal.set_filter("active")
	journal.set_filter("active")
	_report("the journal notifies on an upsert and a filter change", quest_counter.count == 2,
		"count %d" % quest_counter.count)


class SignalCounter extends RefCounted:
	var count := 0

	func bump() -> void:
		count += 1


# ── The ahead-of-corpus view-models (panels.json -> panelTiers) ───────────────

func _test_map_model() -> void:
	var map := InsimulMapModel.new()
	map.set_bounds(-100.0, -100.0, 100.0, 100.0)
	_report("map centre projects to the middle", map.to_map(0.0, 0.0).is_equal_approx(Vector2(0.5, 0.5)),
		"got %s" % str(map.to_map(0.0, 0.0)))
	_report("map corner projects to the origin", map.to_map(-100.0, -100.0).is_equal_approx(Vector2.ZERO),
		"got %s" % str(map.to_map(-100.0, -100.0)))
	_report("map projection round-trips",
		map.to_world(map.to_map(37.0, -12.0)).is_equal_approx(Vector2(37.0, -12.0)),
		"got %s" % str(map.to_world(map.to_map(37.0, -12.0))))

	# A degenerate world (a single point) must not divide by zero.
	var flat := InsimulMapModel.new()
	flat.set_bounds(5.0, 5.0, 5.0, 5.0)
	_report("a degenerate world still projects", is_finite(flat.to_map(5.0, 5.0).x),
		"got %s" % str(flat.to_map(5.0, 5.0)))

	map.set_markers([
		{"id": "m1", "kind": "quest", "x": 0.0, "z": 0.0},
		{"id": "m2", "kind": "settlement", "x": 80.0, "z": 80.0},
		{"id": "m3", "kind": "quest", "x": 10.0, "z": 0.0},
	])
	_report("markers keep insertion order",
		_ids_of(map.markers()) == ["m1", "m2", "m3"], "got %s" % str(_ids_of(map.markers())))
	_report("markers filter by kind",
		_ids_of(map.markers_of_kind(["quest"])) == ["m1", "m3"],
		"got %s" % str(_ids_of(map.markers_of_kind(["quest"]))))
	_report("an empty filter hides nothing", map.markers_of_kind([]).size() == 3,
		"got %d" % map.markers_of_kind([]).size())
	map.set_player_position(0.0, 0.0)
	_report("the minimap slice is the near field",
		_ids_of(map.markers_near(0.0, 0.0, 20.0)) == ["m1", "m3"],
		"got %s" % str(_ids_of(map.markers_near(0.0, 0.0, 20.0))))
	map.upsert_marker({"id": "m1", "kind": "quest", "x": 90.0, "z": 90.0})
	_report("an upsert moves a marker rather than adding one", map.markers().size() == 3,
		"got %d" % map.markers().size())
	_report("a moved marker leaves the near field",
		_ids_of(map.markers_near(0.0, 0.0, 20.0)) == ["m3"],
		"got %s" % str(_ids_of(map.markers_near(0.0, 0.0, 20.0))))
	_report("remove_marker removes exactly one", map.remove_marker("m3") and map.markers().size() == 2,
		"got %d" % map.markers().size())

	# The minimap and the full map share ONE model, so they cannot disagree.
	var minimap := InsimulMinimapPanel.new()
	var fullmap := InsimulFullMapPanel.new()
	minimap.set_model(map)
	fullmap.set_model(map)
	_report("minimap and full map share the marker set", minimap.model() == fullmap.model(),
		"different models")
	fullmap.size = Vector2(400, 400)
	fullmap.set_zoom(1.0)
	fullmap.set_pan(Vector2.ZERO)
	var picked := fullmap.world_for(fullmap.point_for(42.0, -8.0))
	_report("a full-map click round-trips to the world", picked.is_equal_approx(Vector2(42.0, -8.0)),
		"got %s" % str(picked))
	fullmap.set_zoom(99.0)
	_report("zoom is clamped", fullmap.zoom() == InsimulFullMapPanel.ZOOM_MAX, "got %f" % fullmap.zoom())
	minimap.free()
	fullmap.free()


func _test_skill_tree_model() -> void:
	var tree := InsimulSkillTreeModel.new()
	tree.set_nodes([
		{"id": "basics", "name": "Basics", "tier": 1, "cost": 1},
		{"id": "footwork", "name": "Footwork", "tier": 2, "cost": 2, "requires": ["basics"]},
		{"id": "riposte", "name": "Riposte", "tier": 3, "cost": 1, "requires": ["footwork"]},
	])
	_report("tiers are ascending", tree.tiers() == [1, 2, 3], "got %s" % str(tree.tiers()))
	_report("a tier holds its nodes", _ids_of(tree.nodes_in_tier(2)) == ["footwork"],
		"got %s" % str(_ids_of(tree.nodes_in_tier(2))))
	_report("nothing unlocks with no points", not tree.can_unlock("basics"), "unlockable at 0 points")

	tree.set_points(3)
	_report("a root node unlocks", tree.unlock("basics"), "refused")
	_report("the points are spent", tree.points() == 2, "got %d" % tree.points())
	_report("unlocking twice is refused", not tree.unlock("basics"), "unlocked twice")
	_report("a node behind an unmet prerequisite is refused", not tree.can_unlock("riposte"),
		"unlockable with footwork locked")
	_report("the missing prerequisite is named", tree.missing_prerequisites("riposte") == ["footwork"],
		"got %s" % str(tree.missing_prerequisites("riposte")))
	_report("a node whose prerequisite is met unlocks", tree.unlock("footwork"), "refused")
	_report("cost is charged, not assumed", tree.points() == 0, "got %d" % tree.points())
	_report("an affordable node is still refused with no points", not tree.can_unlock("riposte"),
		"unlockable at 0 points")
	tree.grant_points(1)
	_report("a granted point re-opens the node", tree.can_unlock("riposte"), "still refused")
	_report("the unlock set is ordered", tree.unlocked_ids() == ["basics", "footwork"],
		"got %s" % str(tree.unlocked_ids()))

	var view := tree.node_view("riposte")
	_report("the node view carries the three states",
		view.has("unlocked") and view.has("available") and view.has("missing"),
		"got %s" % str(view))

	# A load restores what the save paid for without re-charging.
	var loaded := InsimulSkillTreeModel.new()
	loaded.set_nodes(tree.nodes())
	loaded.set_points(0)
	loaded.restore_unlocked(["basics", "footwork", "not_a_skill"])
	_report("a restore ignores ids the tree does not have", loaded.unlocked_ids() == ["basics", "footwork"],
		"got %s" % str(loaded.unlocked_ids()))
	_report("a restore does not spend points", loaded.points() == 0, "got %d" % loaded.points())


func _test_document_pagination() -> void:
	_report("an empty document is one empty page",
		InsimulDocumentsPanel.paginate("").size() == 1, "got %d" % InsimulDocumentsPanel.paginate("").size())
	var short_doc := InsimulDocumentsPanel.paginate("One paragraph.", 100)
	_report("a short document is one page", short_doc.size() == 1, "got %d" % short_doc.size())
	var two := InsimulDocumentsPanel.paginate("aaaa\n\nbbbb", 6)
	_report("a page break prefers the paragraph boundary", two.size() == 2 and two[0] == "aaaa",
		"got %s" % str(two))
	var long_para := InsimulDocumentsPanel.paginate("x".repeat(25), 10)
	_report("a paragraph longer than a page is split on the count", long_para.size() == 3,
		"got %d pages" % long_para.size())
	_report("no page exceeds the limit", _longest(long_para) <= 10, "longest %d" % _longest(long_para))

	var reader := InsimulDocumentsPanel.new()
	reader.open_document("book1", "A Book", "aaaa\n\nbbbb\n\ncccc")
	_report("opening a document selects the first page", reader.current_page() == 0,
		"got %d" % reader.current_page())
	_report("the reader knows the document", reader.document_id() == "book1", reader.document_id())
	while reader.next_page():
		pass
	_report("the reader stops at the last page rather than wrapping",
		reader.current_page() == reader.page_count() - 1, "got %d" % reader.current_page())
	_report("turning back from the first page is refused",
		not (reader.previous_page() and reader.previous_page() and reader.previous_page()),
		"turned past the start")
	reader.free()


func _test_radial_selection() -> void:
	var wheel := InsimulRadialMenuPanel.new()
	_report("an empty wheel picks nothing", wheel.index_at(Vector2(100, 0)) == -1,
		"got %d" % wheel.index_at(Vector2(100, 0)))
	wheel.set_actions([
		{"id": "a_up", "name": "Up"},
		{"id": "a_right", "name": "Right"},
		{"id": "a_down", "name": "Down"},
		{"id": "a_left", "name": "Left"},
	])
	wheel.open_at(Vector2.ZERO)
	_report("straight up is the first wedge", wheel.index_at(Vector2(0, -100)) == 0,
		"got %d" % wheel.index_at(Vector2(0, -100)))
	_report("clockwise from the top is the second", wheel.index_at(Vector2(100, 0)) == 1,
		"got %d" % wheel.index_at(Vector2(100, 0)))
	_report("straight down is the third", wheel.index_at(Vector2(0, 100)) == 2,
		"got %d" % wheel.index_at(Vector2(0, 100)))
	_report("the last wedge is to the left", wheel.index_at(Vector2(-100, 0)) == 3,
		"got %d" % wheel.index_at(Vector2(-100, 0)))
	_report("the dead zone cancels", wheel.index_at(Vector2(1, 1)) == -1,
		"got %d" % wheel.index_at(Vector2(1, 1)))
	var selected := wheel.select_at(Vector2(100, 0))
	_report("a selection answers the action id", selected == "a_right", "got %s" % selected)
	_report("selecting closes the wheel", not wheel.is_open(), "still open")
	wheel.open_at(Vector2.ZERO)
	var cancelled := wheel.select_at(Vector2.ZERO)
	_report("a dead-zone release cancels without selecting", cancelled == "", "got %s" % cancelled)
	wheel.free()


func _test_quickbar() -> void:
	var bar := InsimulQuickbarPanel.new()
	_report("an unbound slot is empty", bar.slot(0).is_empty(), "got %s" % str(bar.slot(0)))
	_report("firing an empty slot is refused, not an error", not bar.trigger_slot(0), "fired")
	_report("an out-of-range slot is refused", not bar.assign_slot(99, "nope"), "assigned")
	bar.set_actions([{"id": "cast", "name": "Cast"}, {"id": "drink"}])
	_report("the bar binds the action list", String(bar.slot(0).get("id", "")) == "cast",
		"got %s" % str(bar.slot(0)))
	_report("a nameless action falls back to its id", String(bar.slot(1).get("name", "")) == "drink",
		"got %s" % str(bar.slot(1)))
	_report("slots past the action list are cleared", bar.slot(2).is_empty(), "got %s" % str(bar.slot(2)))
	var fired := SignalRecorder.new()
	bar.action_triggered.connect(fired.record)
	_report("a bound slot fires", bar.trigger_slot(0), "refused")
	_report("the fired action is the bound one", fired.last == "cast", "got %s" % fired.last)
	bar.assign_slot(0, "")
	_report("an empty id clears the slot", bar.slot(0).is_empty(), "got %s" % str(bar.slot(0)))
	bar.free()


class SignalRecorder extends RefCounted:
	var last := ""

	func record(_slot: int, action_id: String) -> void:
		last = action_id


func _test_notice_board() -> void:
	var board := InsimulNoticeBoardPanel.new()
	board.set_notices([
		{"id": "n1", "title": "Wolves", "body": "Wolves on the road.", "questId": "q_wolves"},
		{"id": "n2", "title": "Market day", "body": "Tuesday.", "read": true},
	])
	_report("the board counts what is unread", board.unread_count() == 1, "got %d" % board.unread_count())
	_report("an unknown notice cannot be selected", not board.select("nope"), "selected")
	_report("selecting a notice succeeds", board.select("n1"), "refused")
	_report("reading a notice clears its unread mark", board.unread_count() == 0,
		"got %d" % board.unread_count())
	_report("the board knows what is open", board.selected_id() == "n1", board.selected_id())
	var advertised := board.request_quest()
	_report("a notice can advertise a quest", advertised == "q_wolves", advertised)
	board.select("n2")
	var none := board.request_quest()
	_report("a notice with no quest asks for none", none == "", none)
	board.free()


func _ids_of(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(String((e as Dictionary).get("id", "")))
	return out


func _longest(pages: PackedStringArray) -> int:
	var longest := 0
	for page in pages:
		longest = maxi(longest, page.length())
	return longest


# ── Harness ──────────────────────────────────────────────────────────────────
func _run_trade_op(model: InsimulTradeModel, op: Dictionary) -> Dictionary:
	match String(op.get("kind", "")):
		"take":
			return model.take_from_container(String(op.get("container")), String(op.get("item")), int(op.get("qty", 0)))
		"take_all":
			return model.take_all_from_container(String(op.get("container")))
		"buy":
			return model.buy(String(op.get("merchant")), String(op.get("item")), int(op.get("qty")))
		"sell":
			return model.sell(String(op.get("merchant")), String(op.get("item")), int(op.get("qty")))
	return {"ok": false, "reason": "unknown_op", "moved": 0}


func _census(items: Array) -> Dictionary:
	var out := {}
	for i in items:
		var id := String(i.get("itemId", ""))
		out[id] = int(out.get(id, 0)) + int(i.get("quantity", 0))
	return out


func _count(items: Array, item_id: String) -> int:
	return int(_census(items).get(item_id, 0))


func _str_array(v: Variant) -> Array:
	var out: Array = []
	for x in (v if v is Array else []):
		out.append(String(x))
	return out


func _deep_eq(a: Variant, b: Variant) -> bool:
	return _norm(a) == _norm(b)


## A structural, order-independent, JSON-number-tolerant rendering of `v`.
##
## JSON.parse() hands back every number as a FLOAT, so a corpus `4` arrives as
## `4.0` while a model counter is an `int` — comparing str() or JSON.stringify()
## of the two says they differ, and every count/census check in this file failed
## that way the first time this gate was ever executed. Whole floats are therefore
## rendered as integers.
func _norm(v: Variant) -> String:
	if v is Dictionary:
		var keys := (v as Dictionary).keys()
		keys.sort()
		var parts: Array = []
		for k in keys:
			parts.append("%s=%s" % [str(k), _norm(v[k])])
		return "{%s}" % ",".join(parts)
	if v is Array:
		var items: Array = []
		for item in (v as Array):
			items.append(_norm(item))
		return "[%s]" % ",".join(items)
	if v is float:
		var f := float(v)
		return str(int(f)) if is_equal_approx(f, floor(f)) else str(f)
	return str(v)


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[insimul-ui2] FAIL: %s (%s)" % [label, detail])


func _resolve_ui_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--ui" and i + 1 < user_args.size():
			return user_args[i + 1]
	# Standalone layout: the corpus is vendored in this repo, beside addons/.
	return "res://conformance/ui"
