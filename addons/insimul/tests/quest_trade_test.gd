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
	return JSON.stringify(a) == JSON.stringify(b) or _norm(a) == _norm(b)


func _norm(v: Variant) -> Variant:
	# Dictionaries compared order-independently by sorting keys.
	if v is Dictionary:
		var keys := (v as Dictionary).keys()
		keys.sort()
		var parts: Array = []
		for k in keys:
			parts.append("%s=%s" % [str(k), _norm(v[k])])
		return "{%s}" % ",".join(parts)
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
	var script_path := (get_script() as Resource).resource_path
	# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
	var pkg_dir := script_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	var packages_dir := pkg_dir.get_base_dir()
	return packages_dir.path_join("core/conformance/ui")
