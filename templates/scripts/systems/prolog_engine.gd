extends Node
## Prolog Engine — autoloaded singleton.
##
## Thin GDScript adapter over the native **InsimulProlog** GDExtension
## (packages/godot/gdextension), which wraps libinsimul's real Prolog runtime.
## This REPLACES the former substring-matching stub: quest/rule/NPC queries now
## run through genuine unification+resolution instead of `String.contains()`.
##
## Behaviour change (see MIGRATION.md): the old engine "matched" a goal if its
## text appeared anywhere in the KB string; the native engine actually *proves*
## the goal, so unbound variables bind and rules fire. The public method surface
## is preserved so existing/future callers keep compiling.
##
## Graceful degradation: when the GDExtension is not loaded (e.g. the editor
## without the built binary, or a plain `--check-only` parse), `_native_available`
## is false and every query returns a safe permissive default — the game keeps
## running, just without logic-driven gating.

signal quest_completed(quest_id: String)
signal objective_completed(quest_id: String, objective_index: int)

## The native Prolog engine (InsimulProlog, RefCounted). Null when the extension
## isn't registered — see graceful degradation above.
var _prolog: Object = null

## Whether the native InsimulProlog GDExtension is available and instantiated.
var _native_available: bool = false

## Whether initialize() has been called successfully.
var _initialized: bool = false

## Whether debug logging is enabled for Prolog operations.
var debug_logging_enabled: bool = false

## IDs of quests currently being tracked for auto-completion.
var _active_quest_ids: Array[String] = []

## Facts asserted during gameplay (player actions, not world data). These are the
## facts that need to persist across save/load. Dictionary used as a set: keys are
## fact strings (with trailing "."), values are true. Mirrored into the native KB;
## retained here as the array-shaped save bridge alongside snapshot()/restore().
var _player_facts: Dictionary = {}

## Per-item quantities for has_item/3 accuracy.
var _item_quantities: Dictionary = {}

## Tracking for objective and quest completion.
var _completed_objectives: Dictionary = {}  # "questId:idx" -> true
var _completed_quests: Dictionary = {}  # "questId" -> true
var _on_objective_completed: Callable = Callable()
var _on_quest_completed: Callable = Callable()

func _init() -> void:
	_create_engine()

## Instantiate the native InsimulProlog engine if the GDExtension is registered.
## String-based lookup (ClassDB) so this script still parses when the extension
## is absent — the same graceful pattern used by smoke/test_smoke.gd.
func _create_engine() -> void:
	_prolog = null
	_native_available = false
	if ClassDB.class_exists("InsimulProlog"):
		_prolog = ClassDB.instantiate("InsimulProlog")
		_native_available = _prolog != null
	if not _native_available:
		push_warning("[Insimul] InsimulProlog GDExtension not available — Prolog queries degrade to permissive defaults.")

# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------

## Load the knowledge base from exported game data.
## [param data] should contain a "content" key with the .pl text and
## optionally "characters", "settlements", "rules", "actions", "quests".
func initialize(data: Dictionary) -> void:
	# Fresh native KB for a clean load.
	_create_engine()
	_player_facts.clear()
	_item_quantities.clear()
	_completed_objectives.clear()
	_completed_quests.clear()

	# Assemble the world program from the export pipeline + derived facts, then
	# consult it in one pass (real clause loading, not string concatenation).
	var program: String = ""
	if data.has("content"):
		program += str(data["content"]) + "\n"

	for rule in data.get("rules", []):
		if rule.has("content") and not str(rule["content"]).is_empty():
			program += str(rule["content"]) + "\n"
	for action in data.get("actions", []):
		if action.has("content") and not str(action["content"]).is_empty():
			program += str(action["content"]) + "\n"
	for quest in data.get("quests", []):
		if quest.has("content") and not str(quest["content"]).is_empty():
			program += str(quest["content"]) + "\n"

	# Derived character facts
	var characters: Array = data.get("characters", [])
	for ch in characters:
		var char_id: String = _sanitize(
			"%s_%s_%s" % [ch.get("firstName", ""), ch.get("lastName", ""), ch.get("id", "")]
		)
		program += "person(%s).\n" % char_id
		if ch.has("firstName"):
			var full_name: String = "%s %s" % [ch.get("firstName", ""), ch.get("lastName", "")]
			program += "name(%s, '%s').\n" % [char_id, _escape(full_name.strip_edges())]
		if ch.has("age"):
			program += "age(%s, %s).\n" % [char_id, str(ch["age"])]
		if ch.has("occupation"):
			program += "occupation(%s, %s).\n" % [char_id, _sanitize(str(ch["occupation"]))]
		if ch.has("gender"):
			program += "gender(%s, %s).\n" % [char_id, _sanitize(str(ch["gender"]))]
		if ch.has("personality"):
			var p: Dictionary = ch["personality"]
			for trait_name in p:
				program += "personality(%s, %s, %s).\n" % [char_id, _sanitize(str(trait_name)), str(p[trait_name])]
		if ch.has("mood"):
			program += "mood(%s, %s).\n" % [char_id, _sanitize(str(ch["mood"]))]
		if ch.has("energy"):
			program += "energy(%s, %s).\n" % [char_id, str(ch["energy"])]

	# Derived settlement facts
	var settlements: Array = data.get("settlements", [])
	for s in settlements:
		var s_id: String = _sanitize(str(s.get("name", s.get("id", ""))))
		program += "settlement(%s).\n" % s_id
		if s.has("type"):
			program += "settlement_type(%s, %s).\n" % [s_id, _sanitize(str(s["type"]))]

	_consult(program)
	_initialized = true
	print("[Insimul] PrologEngine initialized (native=%s) — KB %d chars" % [str(_native_available), program.length()])


## Sync existing inventory items into the knowledge base.
func initialize_inventory(items: Array) -> void:
	if not _initialized:
		return
	for item in items:
		var item_name: String = _sanitize(str(item.get("name", item.get("id", ""))))
		_assert("has(player, %s)" % item_name)
		if item.has("type") and not str(item["type"]).is_empty():
			_assert("item_type(%s, %s)" % [item_name, _sanitize(str(item["type"]))])
		if item.has("value") and int(item["value"]) > 0:
			_assert("item_value(%s, %d)" % [item_name, int(item["value"])])
	print("[Insimul] PrologEngine inventory: %d items" % items.size())


## Initialize world item definitions into the knowledge base (taxonomy, IS-A chains).
func initialize_world_items(items: Array) -> void:
	if not _initialized:
		return
	for item in items:
		var item_name: String = _sanitize(str(item.get("name", item.get("id", ""))))
		if item.has("itemType") and not str(item["itemType"]).is_empty():
			_assert("item_type(%s, %s)" % [item_name, _sanitize(str(item["itemType"]))])
		if item.has("value") and int(item["value"]) > 0:
			_assert("item_value(%s, %d)" % [item_name, int(item["value"])])
		_assert_item_taxonomy(item_name, item)
	print("[Insimul] PrologEngine world items: %d definitions" % items.size())


## Load built-in IS-A reasoning rules so Prolog can reason hierarchically about items.
func load_item_reasoning_rules() -> void:
	if not _initialized:
		return
	var rules := """
% IS-A reasoning: an item is-a its category
item_is_a(Item, Category) :- item_category(Item, Category).
% IS-A reasoning: an item is-a its base type
item_is_a(Item, BaseType) :- item_base_type(Item, BaseType).
% IS-A reasoning: an item is-a its item type
item_is_a(Item, Type) :- item_type(Item, Type).

% Check if player has any item of a given category/type
has_item_of_type(Player, Type) :- has(Player, Item), item_is_a(Item, Type).

% Check if player has at least N of an item
has_at_least(Player, Item, N) :- has_item(Player, Item, Qty), Qty >= N.
"""
	_consult(rules)
	print("[Insimul] PrologEngine loaded item reasoning rules")


## Load gameplay helper predicates (CEFR comparison, weapon/tool types, skill checks).
func load_helper_predicates() -> void:
	if not _initialized:
		return
	var rules := """
% CEFR level ranks
cefr_level_rank(a1, 1).
cefr_level_rank(a2, 2).
cefr_level_rank(b1, 3).
cefr_level_rank(b2, 4).
cefr_level_rank(c1, 5).
cefr_level_rank(c2, 6).
cefr_gte(Actual, Required) :- cefr_level_rank(Actual, AR), cefr_level_rank(Required, RR), AR >= RR.

% Weapon type classification
is_weapon_type(ItemId, sword) :- item_type(ItemId, sword).
is_weapon_type(ItemId, axe) :- item_type(ItemId, axe).
is_weapon_type(ItemId, bow) :- item_type(ItemId, bow).
is_weapon_type(ItemId, staff) :- item_type(ItemId, staff).
is_weapon_type(ItemId, pistol) :- item_type(ItemId, pistol).

% Tool type classification
is_tool_type(ItemId, fishing_rod) :- item_type(ItemId, fishing_rod).
is_tool_type(ItemId, pickaxe) :- item_type(ItemId, pickaxe).
is_tool_type(ItemId, axe) :- item_type(ItemId, axe).
is_tool_type(ItemId, hoe) :- item_type(ItemId, hoe).

% Skill tier names
skill_tier_name(1, novice).
skill_tier_name(2, novice).
skill_tier_name(3, apprentice).
skill_tier_name(4, apprentice).
skill_tier_name(5, journeyman).
skill_tier_name(6, journeyman).
skill_tier_name(7, expert).
skill_tier_name(8, expert).
skill_tier_name(9, expert).
skill_tier_name(10, master).

% Skill level comparison
skill_gte(Actor, Skill, MinLevel) :- has_skill(Actor, Skill, Level), Level >= MinLevel.
"""
	_consult(rules)
	print("[Insimul] PrologEngine loaded gameplay helper predicates")


# ---------------------------------------------------------------------------
# Game-state updates
# ---------------------------------------------------------------------------

## Update dynamic player state facts. Call on each significant state change.
func update_game_state(state: Dictionary) -> void:
	if not _initialized:
		return
	var player_id: String = _sanitize(str(state.get("playerCharacterId", "player")))

	# Retract stale dynamic facts (real retract by matching term).
	_retract_all("energy(%s, _)" % player_id)
	_retract_all("at_location(%s, _)" % player_id)
	_retract_all("nearby_npc(%s, _)" % player_id)

	_assert("energy(%s, %s)" % [player_id, str(state.get("playerEnergy", 100))])

	var settlement: String = str(state.get("currentSettlement", ""))
	if not settlement.is_empty():
		_assert("at_location(%s, %s)" % [player_id, _sanitize(settlement)])

	var nearby: Array = state.get("nearbyNPCs", [])
	for npc_id in nearby:
		_assert("nearby_npc(%s, %s)" % [player_id, _sanitize(str(npc_id))])

	if state.has("gameHour") or state.has("weather"):
		update_environment(state)


## Update environment awareness facts (weather, time, player progress).
func update_environment(env: Dictionary) -> void:
	if not _initialized:
		return

	_retract_all("game_hour(_)")
	_retract_all("time_period(_)")
	_retract_all("time_of_day(_)")
	_retract_all("weather(_)")
	_retract_all("season(_)")
	_retract_all("player_quests_completed(_)")
	_retract_all("player_reputation(_)")
	_retract_all("player_is_new")

	var hour: int = int(env.get("gameHour", 12))
	_assert("game_hour(%d)" % hour)

	var period: String
	if hour >= 5 and hour < 7:
		period = "dawn"
	elif hour >= 7 and hour < 12:
		period = "morning"
	elif hour >= 12 and hour < 17:
		period = "afternoon"
	elif hour >= 17 and hour < 21:
		period = "evening"
	else:
		period = "night"
	_assert("time_period(%s)" % period)

	var schedule_time: String
	if hour < 12:
		schedule_time = "morning"
	elif hour < 17:
		schedule_time = "afternoon"
	elif hour < 21:
		schedule_time = "evening"
	else:
		schedule_time = "night"
	_assert("time_of_day(%s)" % schedule_time)

	var weather: String = str(env.get("weather", "clear"))
	_assert("weather(%s)" % _sanitize(weather))

	if env.has("season") and not str(env["season"]).is_empty():
		_assert("season(%s)" % _sanitize(str(env["season"])))
	if env.has("questsCompleted") and int(env["questsCompleted"]) >= 0:
		_assert("player_quests_completed(%d)" % int(env["questsCompleted"]))
	if env.has("reputation") and float(env["reputation"]) != 0.0:
		_assert("player_reputation(%d)" % int(env["reputation"]))
	if env.get("isNewToTown", false):
		_assert("player_is_new")


## Check if an NPC should mention weather in conversation.
func should_mention_weather(npc_id: String) -> bool:
	if not _initialized:
		return false
	return _holds("weather_complaint_likely(%s)" % _sanitize(npc_id))


## Get the NPC's attitude toward the player based on progress.
func get_player_attitude(npc_id: String) -> String:
	if not _initialized:
		return "neutral"
	var id: String = _sanitize(npc_id)
	if _holds("impressed_by_player(%s)" % id):
		return "impressed"
	if _holds("respects_player(%s)" % id):
		return "respectful"
	if _holds("wary_of_newcomer(%s)" % id):
		return "wary"
	if _holds("welcoming_to_newcomer(%s)" % id):
		return "welcoming"
	return "neutral"


# ---------------------------------------------------------------------------
# Action / quest queries
# ---------------------------------------------------------------------------

## Check if an action is allowed. Returns {allowed: bool, reason: String}.
## Blocked if the KB proves a matching "cannot_perform" goal.
func can_perform_action(action_id: String, actor_id: String, target_id: String = "") -> Dictionary:
	if not _initialized:
		return {"allowed": true, "reason": ""}
	var action_atom: String = _sanitize(action_id)
	var actor_atom: String = _sanitize(actor_id)

	var goal: String
	if target_id.is_empty():
		goal = "cannot_perform(%s, %s)" % [actor_atom, action_atom]
	else:
		goal = "cannot_perform(%s, %s, %s)" % [actor_atom, action_atom, _sanitize(target_id)]

	if _holds(goal):
		return {"allowed": false, "reason": "Prerequisites not met for action: %s" % action_id}
	return {"allowed": true, "reason": ""}


## Check if a quest is available to the player.
func is_quest_available(quest_id: String, player_id: String) -> bool:
	if not _initialized:
		return true
	var q_atom: String = _sanitize(quest_id)
	var p_atom: String = _sanitize(player_id)
	# Blocked if the KB proves quest_unavailable.
	if _holds("quest_unavailable(%s, %s)" % [p_atom, q_atom]):
		return false
	# Default: available (an explicit quest_available proof also counts).
	return true


## Check if a quest is complete for the player.
func is_quest_complete(quest_id: String, player_id: String) -> bool:
	if not _initialized:
		return false
	var q_atom: String = _sanitize(quest_id)
	var p_atom: String = _sanitize(player_id)
	return _holds("quest_complete(%s, %s)" % [p_atom, q_atom]) or \
		   _holds("quest_completed(%s, %s)" % [p_atom, q_atom])


## Check if a specific quest stage is complete.
func is_stage_complete(quest_id: String, stage_id: String, player_id: String) -> bool:
	if not _initialized:
		return false
	var q_atom: String = _sanitize(quest_id)
	var s_atom: String = _sanitize(stage_id)
	var p_atom: String = _sanitize(player_id)
	return _holds("stage_complete(%s, %s, %s)" % [p_atom, q_atom, s_atom])


## Evaluate a Prolog goal condition. Returns true if the goal is provable.
func evaluate_condition(prolog_goal: String) -> bool:
	if not _initialized:
		return true
	var clean: String = prolog_goal.strip_edges().trim_suffix(".")
	if clean.is_empty():
		return true
	return _holds(clean)


## Return rule names that apply to the given actor via rule_applies(Rule, actor).
func get_applicable_rules(actor_id: String) -> Array[String]:
	if not _initialized:
		return []
	var actor_atom: String = _sanitize(actor_id)
	return _query_var("rule_applies(RuleName, %s)" % actor_atom, "RuleName")


## Get engine stats for debugging.
func get_stats() -> Dictionary:
	var fact_count: int = 0
	if _native_available and _prolog != null:
		var image: String = str(_prolog.snapshot())
		for line in image.split("\n"):
			if not line.strip_edges().is_empty():
				fact_count += 1
	return {"fact_count": fact_count, "native": _native_available}

# ---------------------------------------------------------------------------
# Fact management
# ---------------------------------------------------------------------------

## Assert a new fact into the dynamic fact store.
func assert_fact(fact: String, source: String = "") -> void:
	if not _initialized:
		return
	_assert(fact)
	_reevaluate_quests()
	if debug_logging_enabled:
		var source_info: String = " (source: %s)" % source if source != "" else ""
		print("[PrologDebug] assert: %s%s" % [fact.strip_edges().trim_suffix("."), source_info])


## Retract a fact from the dynamic fact store.
func retract_fact(fact: String, reason: String = "") -> void:
	if not _initialized:
		return
	_retract(fact)
	_reevaluate_quests()
	if debug_logging_enabled:
		var reason_info: String = " (reason: %s)" % reason if reason != "" else ""
		print("[PrologDebug] retract: %s%s" % [fact.strip_edges().trim_suffix("."), reason_info])


## Run a query against the knowledge base.
## Returns an array of dictionaries with variable bindings (one per solution).
func query(goal: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if not _initialized:
		return results
	for sol in _query(goal):
		if sol is Dictionary:
			results.append(sol)
	if debug_logging_enabled:
		var success: String = "true" if results.size() > 0 else "false"
		print("[PrologDebug] query: %s -> %s (%d results)" % [goal.strip_edges().trim_suffix("."), success, results.size()])
	return results


## Export the dynamic-fact set as canonical Prolog text.
## @deprecated Use save_snapshot()/get_player_facts() for save/load.
func export_knowledge_base() -> String:
	if _native_available and _prolog != null:
		return str(_prolog.snapshot())
	return ""

# ---------------------------------------------------------------------------
# NPC intelligence queries
# ---------------------------------------------------------------------------

## Determine which NPCs the given NPC should talk to.
func who_should_talk_to(npc_id: String) -> Array[String]:
	if not _initialized:
		return []
	return _query_var("should_talk_to(%s, Target)" % _sanitize(npc_id), "Target")


## Check if an NPC wants to socialize.
func wants_to_socialize(npc_id: String) -> bool:
	if not _initialized:
		return false
	return _holds("wants_to_socialize(%s)" % _sanitize(npc_id))


## Check if this is a first meeting (no mental model exists).
func is_first_meeting(npc_id: String, player_id: String) -> bool:
	if not _initialized:
		return true
	var npc_atom: String = _sanitize(npc_id)
	var player_atom: String = _sanitize(player_id)
	return not _holds("has_mental_model(%s, %s)" % [npc_atom, player_atom])


## Get preferred dialogue topics for an NPC.
func get_preferred_topics(npc_id: String) -> Array[String]:
	if not _initialized:
		return []
	return _query_var("prefers_topic(%s, Topic)" % _sanitize(npc_id), "Topic")


## Get an NPC's conflict resolution style.
func get_conflict_style(npc_id: String) -> String:
	if not _initialized:
		return ""
	var results: Array[String] = _query_var("conflict_style(%s, Style)" % _sanitize(npc_id), "Style")
	return results[0] if results.size() > 0 else ""


## Check if an NPC is grieving.
func is_grieving(npc_id: String) -> bool:
	if not _initialized:
		return false
	return _holds("is_grieving(%s)" % _sanitize(npc_id))


## Get NPCs that should be avoided by a given NPC.
func who_to_avoid(npc_id: String) -> Array[String]:
	if not _initialized:
		return []
	return _query_var("should_avoid(%s, Target)" % _sanitize(npc_id), "Target")


## Check if an NPC is willing to share knowledge with another.
func is_willing_to_share(npc_id: String, target_id: String) -> bool:
	if not _initialized:
		return true
	var npc_atom: String = _sanitize(npc_id)
	var target_atom: String = _sanitize(target_id)
	return _holds("willing_to_share(%s, %s)" % [npc_atom, target_atom])


## Evaluate volition rules for an NPC. Returns scored actions sorted descending.
func evaluate_volition_rules(npc_id: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if not _initialized:
		return results
	var npc_atom: String = _sanitize(npc_id)
	for sol in _query("volition_score(%s, Action, Target, Score)" % npc_atom):
		if sol is Dictionary:
			results.append({
				"action_id": str(sol.get("Action", "")),
				"target_id": str(sol.get("Target", "")),
				"score": float(sol.get("Score", 0))
			})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("score", 0)) > float(b.get("score", 0)))
	return results


## Get the current romance stage between the player and an NPC.
func get_romance_stage(npc_id: String) -> String:
	if not _initialized:
		return ""
	var results: Array[String] = _query_var("romance_stage(player, %s, Stage)" % _sanitize(npc_id), "Stage")
	return results[0] if results.size() > 0 else ""


## Check if a romance action can be performed with an NPC.
## Returns true by default if no romance rules are loaded.
func can_perform_romance_action(npc_id: String, action_type: String) -> bool:
	if not _initialized:
		return true
	var npc_atom: String = _sanitize(npc_id)
	var action_atom: String = _sanitize(action_type)
	# If no romance rules loaded at all, allow by default (graceful degradation).
	if not _holds("can_romance_action(_, _, _)"):
		return true
	return _holds("can_romance_action(player, %s, %s)" % [npc_atom, action_atom])


## Update NPC personality facts. Retracts old personality facts, asserts new ones.
func update_npc_personality(npc_id: String, personality: Dictionary) -> void:
	if not _initialized:
		return
	var id: String = _sanitize(npc_id)
	_retract_all("personality(%s, _, _)" % id)
	for trait_name in personality:
		_assert("personality(%s, %s, %s)" % [id, _sanitize(str(trait_name)), str(personality[trait_name])])


## Update NPC emotional state.
func update_npc_emotional_state(npc_id: String, state: Dictionary) -> void:
	if not _initialized:
		return
	var id: String = _sanitize(npc_id)
	_retract_all("mood(%s, _)" % id)
	_retract_all("stress_level(%s, _)" % id)
	_retract_all("social_desire(%s, _)" % id)
	_retract_all("energy(%s, _)" % id)
	if state.has("mood"):
		_assert("mood(%s, %s)" % [id, _sanitize(str(state["mood"]))])
	if state.has("stressLevel"):
		_assert("stress_level(%s, %s)" % [id, str(state["stressLevel"])])
	if state.has("socialDesire"):
		_assert("social_desire(%s, %s)" % [id, str(state["socialDesire"])])
	if state.has("energy"):
		_assert("energy(%s, %s)" % [id, str(state["energy"])])


## Update NPC relationship facts.
func update_npc_relationship(npc1_id: String, npc2_id: String, relationship: Dictionary) -> void:
	if not _initialized:
		return
	var id1: String = _sanitize(npc1_id)
	var id2: String = _sanitize(npc2_id)
	_retract_all("relationship_charge(%s, %s, _)" % [id1, id2])
	_retract_all("relationship_trust(%s, %s, _)" % [id1, id2])
	_retract_all("conversation_count(%s, %s, _)" % [id1, id2])
	_retract_all("friends(%s, %s)" % [id1, id2])
	_retract_all("enemies(%s, %s)" % [id1, id2])
	if relationship.has("charge"):
		_assert("relationship_charge(%s, %s, %s)" % [id1, id2, str(relationship["charge"])])
	if relationship.has("trust"):
		_assert("relationship_trust(%s, %s, %s)" % [id1, id2, str(relationship["trust"])])
	if relationship.has("conversationCount"):
		_assert("conversation_count(%s, %s, %s)" % [id1, id2, str(relationship["conversationCount"])])
	if relationship.get("isFriend", false):
		_assert("friends(%s, %s)" % [id1, id2])
	if relationship.get("isEnemy", false):
		_assert("enemies(%s, %s)" % [id1, id2])


## Record that the player performed an action on an NPC.
func record_player_action(player_id: String, npc_id: String, action_name: String) -> void:
	if not _initialized:
		return
	var p_id: String = _sanitize(player_id)
	var n_id: String = _sanitize(npc_id)
	var action: String = _sanitize(action_name)
	_assert("player_action(%s, %s, %s)" % [p_id, n_id, action])

# ---------------------------------------------------------------------------
# Player fact tracking (save/load)
# ---------------------------------------------------------------------------

## Assert a fact and track it as a player-gameplay fact for save/load.
func _assert_player_fact(fact: String) -> void:
	_assert(fact)
	var clean: String = fact.strip_edges().trim_suffix(".")
	_player_facts[clean + "."] = true


## Retract a fact and remove it from player-gameplay tracking.
func _retract_player_fact(fact: String) -> void:
	var clean: String = fact.strip_edges().trim_suffix(".")
	_retract(clean)
	_player_facts.erase(clean + ".")


## Retract player facts by predicate + leading args, cleaning up tracking.
func _retract_player_fact_by_pattern(predicate: String, first_arg: String, second_arg: String = "") -> void:
	var prefix: String
	if second_arg != "":
		prefix = "%s(%s, %s" % [predicate, first_arg, second_arg]
	else:
		prefix = "%s(%s" % [predicate, first_arg]
	# Remove matching entries from _player_facts and retract each from the KB.
	var to_remove: Array = []
	for key in _player_facts:
		if str(key).begins_with(prefix):
			to_remove.append(key)
	for key in to_remove:
		_retract(str(key))
		_player_facts.erase(key)


## Update item quantity and track the facts for save/load.
func _update_item_quantity_tracked(item_name: String, delta: int) -> void:
	var old_qty: int = _get_item_quantity(item_name)
	var new_qty: int = max(0, old_qty + delta)
	_item_quantities[item_name] = new_qty
	_retract_player_fact_by_pattern("has_item", "player", item_name)
	if new_qty > 0:
		_assert_player_fact("has_item(player, %s, %d)" % [item_name, new_qty])


## Assert taxonomy facts for an item with player-fact tracking.
func _assert_item_taxonomy_tracked(item_name: String, taxonomy: Dictionary) -> void:
	if taxonomy.has("category") and not str(taxonomy["category"]).is_empty():
		_assert_player_fact("item_category(%s, %s)" % [item_name, _sanitize(str(taxonomy["category"]))])
		_assert_player_fact("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["category"]))])
	if taxonomy.has("material") and not str(taxonomy["material"]).is_empty():
		_assert_player_fact("item_material(%s, %s)" % [item_name, _sanitize(str(taxonomy["material"]))])
	if taxonomy.has("base_type") and not str(taxonomy["base_type"]).is_empty():
		_assert_player_fact("item_base_type(%s, %s)" % [item_name, _sanitize(str(taxonomy["base_type"]))])
		_assert_player_fact("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["base_type"]))])
	elif taxonomy.has("baseType") and not str(taxonomy["baseType"]).is_empty():
		_assert_player_fact("item_base_type(%s, %s)" % [item_name, _sanitize(str(taxonomy["baseType"]))])
		_assert_player_fact("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["baseType"]))])
	if taxonomy.has("rarity") and not str(taxonomy["rarity"]).is_empty():
		_assert_player_fact("item_rarity(%s, %s)" % [item_name, _sanitize(str(taxonomy["rarity"]))])
	if taxonomy.has("item_type") and not str(taxonomy["item_type"]).is_empty():
		_assert_player_fact("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["item_type"]))])
	elif taxonomy.has("itemType") and not str(taxonomy["itemType"]).is_empty():
		_assert_player_fact("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["itemType"]))])


## Get all player-asserted facts (gameplay facts only, not world data).
## Array-shaped save bridge; save_snapshot() is the native canonical form.
func get_player_facts() -> Array:
	return _player_facts.keys()


## Serialize the dynamic-fact set as canonical Prolog text (native snapshot).
func save_snapshot() -> String:
	if _native_available and _prolog != null:
		return str(_prolog.snapshot())
	return ""


## Restore the dynamic-fact set from a canonical snapshot image (native restore).
func restore_snapshot(image: String) -> bool:
	if not _native_available or _prolog == null:
		return false
	return _prolog.restore(image)


## Restore player facts from a saved array. Call after initialize().
func restore_player_facts(facts: Array) -> void:
	if not _initialized:
		return
	for fact_with_dot in facts:
		var fact: String = str(fact_with_dot)
		if fact.ends_with("."):
			fact = fact.substr(0, fact.length() - 1)
		fact = fact.strip_edges()
		if fact.is_empty():
			continue
		_assert(fact)
		_player_facts[fact + "."] = true
		var regex := RegEx.new()
		regex.compile("^has_item\\(player,\\s*(\\S+),\\s*(\\d+)\\)$")
		var match_result := regex.search(fact)
		if match_result:
			_item_quantities[match_result.get_string(1)] = int(match_result.get_string(2))
	print("[Insimul] PrologEngine restored %d player facts from save" % facts.size())


## Reconstruct Prolog facts from structured save state data.
func restore_from_save_state(state: Dictionary) -> void:
	if not _initialized:
		return
	var restored_count: int = 0

	# 1. Inventory
	var inventory: Array = state.get("player", {}).get("inventory", [])
	for item in inventory:
		var item_name: String = _sanitize(str(item.get("name", item.get("id", ""))))
		var qty: int = int(item.get("quantity", 1))
		_assert_player_fact("has(player, %s)" % item_name)
		_assert_player_fact("has_item(player, %s, %d)" % [item_name, qty])
		_item_quantities[item_name] = qty
		if item.has("type") and not str(item["type"]).is_empty():
			_assert_player_fact("item_type(%s, %s)" % [item_name, _sanitize(str(item["type"]))])
		if item.has("category") and not str(item["category"]).is_empty():
			_assert_player_fact("item_category(%s, %s)" % [item_name, _sanitize(str(item["category"]))])
			_assert_player_fact("item_is_a(%s, %s)" % [item_name, _sanitize(str(item["category"]))])
		if item.has("baseType") and not str(item["baseType"]).is_empty():
			_assert_player_fact("item_base_type(%s, %s)" % [item_name, _sanitize(str(item["baseType"]))])
			_assert_player_fact("item_is_a(%s, %s)" % [item_name, _sanitize(str(item["baseType"]))])
		if item.has("material") and not str(item["material"]).is_empty():
			_assert_player_fact("item_material(%s, %s)" % [item_name, _sanitize(str(item["material"]))])
		if item.has("rarity") and not str(item["rarity"]).is_empty():
			_assert_player_fact("item_rarity(%s, %s)" % [item_name, _sanitize(str(item["rarity"]))])
		if item.get("equipped", false) and item.has("equipSlot"):
			_assert_player_fact("equipped(player, %s, %s)" % [item_name, _sanitize(str(item["equipSlot"]))])
		restored_count += 1

	# 2. Quests
	var quest_state: Dictionary = state.get("questActiveState", {}).get("quests", {})
	for quest_id in quest_state:
		var q_id: String = _sanitize(str(quest_id))
		var q_status: String = str(quest_state[quest_id].get("status", ""))
		if q_status == "active":
			_assert_player_fact("quest_active(player, %s)" % q_id)
		elif q_status == "completed":
			_assert_player_fact("quest_completed(player, %s)" % q_id)
		elif q_status == "failed":
			_assert_player_fact("quest_failed(player, %s)" % q_id)
		restored_count += 1

	# 3. Conversations
	var conversations: Array = state.get("conversations", [])
	for conv in conversations:
		var npc_id: String = _sanitize(str(conv.get("npcId", "")))
		var turn_count: int = int(conv.get("turnCount", 0))
		_assert_player_fact("talked_to(player, %s, %s)" % [npc_id, str(turn_count)])
		_assert_player_fact("npc_conversation_turns(player, %s, %s)" % [npc_id, str(turn_count)])
		restored_count += 1

	# 4. Contacts / NPC-met
	var contacts: Dictionary = state.get("contacts", {})
	for npc_id in contacts:
		var sanitized_npc: String = _sanitize(str(npc_id))
		var conv_count: int = int(contacts[npc_id].get("conversationCount", 0))
		if conv_count > 0:
			_assert_player_fact("talked_to(player, %s, %s)" % [sanitized_npc, str(conv_count)])
		restored_count += 1

	# 5. Reputation
	var rep_entries: Array = state.get("reputationState", {}).get("entries", [])
	for entry in rep_entries:
		var entity_id: String = _sanitize(str(entry.get("entityId", "")))
		var score: int = int(entry.get("score", 0))
		_assert_player_fact("reputation_change(player, %s, %s)" % [entity_id, str(score)])
		restored_count += 1

	# 6. Current location
	if state.has("currentZone") and state["currentZone"] is Dictionary:
		var zone_id: String = _sanitize(str(state["currentZone"].get("id", "")))
		if not zone_id.is_empty():
			_assert_player_fact("visited(player, %s)" % zone_id)
			restored_count += 1

	# 7. Reading progress
	var articles: Dictionary = state.get("readingProgress", {}).get("articles", {})
	for article_id in articles:
		if articles[article_id].get("read", false):
			_assert_player_fact("text_read(player, %s)" % _sanitize(str(article_id)))
			restored_count += 1

	# 8. CEFR level
	var cefr_level: String = str(state.get("player", {}).get("cefrLevel", ""))
	if not cefr_level.is_empty():
		_assert_player_fact("player_cefr_level(player, %s)" % _sanitize(cefr_level))
		restored_count += 1

	# 9. Additional player facts with no structured equivalent
	var prolog_facts_str: String = str(state.get("prologFacts", ""))
	if not prolog_facts_str.is_empty():
		var parsed = JSON.parse_string(prolog_facts_str)
		if parsed is Array:
			for fact_with_dot in parsed:
				var fact: String = str(fact_with_dot)
				if fact.ends_with("."):
					fact = fact.substr(0, fact.length() - 1)
				fact = fact.strip_edges()
				if fact.is_empty():
					continue
				if _player_facts.has(fact + "."):
					continue
				_assert(fact)
				_player_facts[fact + "."] = true
				var regex := RegEx.new()
				regex.compile("^has_item\\(player,\\s*(\\S+),\\s*(\\d+)\\)$")
				var match_result := regex.search(fact)
				if match_result:
					_item_quantities[match_result.get_string(1)] = int(match_result.get_string(2))
				restored_count += 1

	print("[Insimul] PrologEngine restored %d facts from save state" % restored_count)
	_reevaluate_quests()

# ---------------------------------------------------------------------------
# Event bus integration
# ---------------------------------------------------------------------------

## Reference to connected event bus.
var _event_bus: Node = null
var _event_bus_handler: Callable = Callable()


## Subscribe to an EventBus, asserting Prolog facts for each game event.
func subscribe_to_event_bus(event_bus: Node) -> void:
	if _event_bus != null and _event_bus_handler.is_valid():
		if _event_bus.has_method("disconnect_any"):
			_event_bus.disconnect_any(_event_bus_handler)
	_event_bus = event_bus
	_event_bus_handler = _handle_game_event
	if event_bus.has_method("connect_any"):
		event_bus.connect_any(_event_bus_handler)


## Handle a game event by asserting the corresponding Prolog facts.
func _handle_game_event(event: Dictionary) -> void:
	if not _initialized:
		return
	var event_type: String = event.get("type", "")
	match event_type:
		"item_collected":
			var name: String = _sanitize(str(event.get("item_name", "")))
			_assert_player_fact("collected(player, %s, %s)" % [name, str(event.get("quantity", 1))])
			_assert_player_fact("has(player, %s)" % name)
			_update_item_quantity_tracked(name, int(event.get("quantity", 1)))
			if event.has("taxonomy"):
				_assert_item_taxonomy_tracked(name, event["taxonomy"])
		"enemy_defeated":
			_assert_player_fact("defeated(player, %s)" % _sanitize(str(event.get("enemy_type", ""))))
		"location_visited":
			_assert_player_fact("visited(player, %s)" % _sanitize(str(event.get("location_id", ""))))
		"npc_talked":
			_assert_player_fact("talked_to(player, %s, %s)" % [_sanitize(str(event.get("npc_id", ""))), str(event.get("turn_count", 0))])
		"item_delivered":
			_assert_player_fact("delivered(player, %s, %s)" % [_sanitize(str(event.get("npc_id", ""))), _sanitize(str(event.get("item_name", "")))])
		"vocabulary_used":
			var correct_val: int = 1 if event.get("correct", false) else 0
			_assert_player_fact("vocab_used(player, %s, %s)" % [_sanitize(str(event.get("word", ""))), str(correct_val)])
		"item_crafted":
			var name: String = _sanitize(str(event.get("item_name", "")))
			_assert_player_fact("crafted(player, %s, %s)" % [name, str(event.get("quantity", 1))])
			_assert_player_fact("has(player, %s)" % name)
			_update_item_quantity_tracked(name, int(event.get("quantity", 1)))
			if event.has("taxonomy"):
				_assert_item_taxonomy_tracked(name, event["taxonomy"])
		"location_discovered":
			_assert_player_fact("discovered(player, %s)" % _sanitize(str(event.get("location_id", ""))))
		"settlement_entered":
			_assert_player_fact("visited(player, %s)" % _sanitize(str(event.get("settlement_id", ""))))
		"reputation_changed":
			_assert_player_fact("reputation_change(player, %s, %s)" % [_sanitize(str(event.get("faction_id", ""))), str(event.get("delta", 0))])
		"quest_accepted":
			var qid: String = _sanitize(str(event.get("quest_id", "")))
			_assert_player_fact("quest_active(player, %s)" % qid)
			var npc_id: String = str(event.get("assigned_by_npc_id", ""))
			if npc_id != "":
				_assert_player_fact("npc_gave_quest(%s, player, %s)" % [_sanitize(npc_id), qid])
		"quest_completed":
			var qid: String = _sanitize(str(event.get("quest_id", "")))
			_assert_player_fact("quest_completed(player, %s)" % qid)
			var npc_id: String = str(event.get("assigned_by_npc_id", ""))
			if npc_id != "":
				_assert_player_fact("quest_outcome(%s, player, completed)" % qid)
		"puzzle_solved":
			_assert_player_fact("puzzle_solved(player, %s)" % _sanitize(str(event.get("puzzle_id", ""))))
		"item_removed", "item_dropped":
			var name: String = _sanitize(str(event.get("item_name", "")))
			var qty: int = int(event.get("quantity", 1))
			_update_item_quantity_tracked(name, -qty)
			if _get_item_quantity(name) <= 0:
				_retract_player_fact("has(player, %s)" % name)
		"item_used":
			var name: String = _sanitize(str(event.get("item_name", "")))
			_update_item_quantity_tracked(name, -1)
			if _get_item_quantity(name) <= 0:
				_retract_player_fact("has(player, %s)" % name)
		"item_equipped":
			_assert_player_fact("equipped(player, %s, %s)" % [_sanitize(str(event.get("item_name", ""))), _sanitize(str(event.get("slot", "")))])
		"item_unequipped":
			_retract_player_fact("equipped(player, %s, %s)" % [_sanitize(str(event.get("item_name", ""))), _sanitize(str(event.get("slot", "")))])
		"romance_action":
			var npc_id: String = _sanitize(str(event.get("npc_id", "")))
			var action_type: String = _sanitize(str(event.get("action_type", "")))
			var status: String = "accepted" if event.get("accepted", false) else "rejected"
			_assert_player_fact("romance_action(player, %s, %s, %s)" % [npc_id, action_type, status])
			if event.get("accepted", false) and _event_bus != null and _event_bus.has_method("emit_event"):
				_event_bus.emit_event({
					"type": "state_created_truth",
					"character_id": "player",
					"title": "Romance: %s with %s" % [str(event.get("action_type", "")), str(event.get("npc_name", ""))],
					"content": "Player performed %s on %s" % [str(event.get("action_type", "")), str(event.get("npc_name", ""))],
					"entry_type": "romance"
				})
		"romance_stage_changed":
			var npc_id: String = _sanitize(str(event.get("npc_id", "")))
			var from_stage: String = _sanitize(str(event.get("from_stage", "")))
			var to_stage: String = _sanitize(str(event.get("to_stage", "")))
			_retract_player_fact_by_pattern("romance_stage", "player", npc_id)
			_assert_player_fact("romance_stage(player, %s, %s)" % [npc_id, to_stage])
			_assert_player_fact("romance_history(player, %s, %s, %s)" % [npc_id, from_stage, to_stage])
			if _event_bus != null and _event_bus.has_method("emit_event"):
				_event_bus.emit_event({
					"type": "state_created_truth",
					"character_id": "player",
					"title": "Romance stage: %s -> %s with %s" % [str(event.get("from_stage", "")), str(event.get("to_stage", "")), str(event.get("npc_name", ""))],
					"content": "Romance stage changed from %s to %s" % [str(event.get("from_stage", "")), str(event.get("to_stage", ""))],
					"entry_type": "romance"
				})
		"npc_volition_action":
			_assert_player_fact("volition_acted(%s, %s, %s)" % [_sanitize(str(event.get("npc_id", ""))), _sanitize(str(event.get("action_id", ""))), _sanitize(str(event.get("target_id", "")))])
		"conversation_overheard":
			_assert_player_fact("overheard_conversation(player, %s, %s, %s)" % [_sanitize(str(event.get("npc_id_1", ""))), _sanitize(str(event.get("npc_id_2", ""))), _sanitize(str(event.get("topic", "")))])
		"state_created_truth":
			_assert_player_fact("has_state(%s, %s)" % [_sanitize(str(event.get("character_id", ""))), _sanitize(str(event.get("state_type", "")))])
		"state_expired_truth":
			_retract_player_fact("has_state(%s, %s)" % [_sanitize(str(event.get("character_id", ""))), _sanitize(str(event.get("state_type", "")))])
		"puzzle_failed":
			_assert_player_fact("puzzle_failed(player, %s, %s)" % [_sanitize(str(event.get("puzzle_id", ""))), str(event.get("attempts", 0))])
		"quest_failed":
			var qid: String = _sanitize(str(event.get("quest_id", "")))
			_assert_player_fact("quest_failed(player, %s)" % qid)
			var npc_id: String = str(event.get("assigned_by_npc_id", ""))
			if npc_id != "":
				_assert_player_fact("quest_outcome(%s, player, failed)" % qid)
		"quest_abandoned":
			var qid: String = _sanitize(str(event.get("quest_id", "")))
			_assert_player_fact("quest_abandoned(player, %s)" % qid)
			var npc_id: String = str(event.get("assigned_by_npc_id", ""))
			if npc_id != "":
				_assert_player_fact("quest_outcome(%s, player, abandoned)" % qid)
			_retract_player_fact_by_pattern("quest_active", "player", qid)
		"direction_step_completed":
			var dqid: String = _sanitize(str(event.get("quest_id", "")))
			_retract_player_fact_by_pattern("quest_progress", "player", dqid)
			_assert_player_fact("quest_progress(player, %s, %s)" % [dqid, str(event.get("steps_completed", 0))])
			_assert_player_fact("direction_step_done(player, %s, %s)" % [dqid, str(event.get("step_index", 0))])
		"conversational_action_completed":
			var npc_id: String = _sanitize(str(event.get("npc_id", "")))
			var action: String = _sanitize(str(event.get("action", "")))
			var qid: String = _sanitize(str(event.get("quest_id", "")))
			_assert_player_fact("conversational_action(player, %s, %s, %s)" % [npc_id, action, qid])
		"text_found":
			_assert_player_fact("text_found(player, %s)" % _sanitize(str(event.get("text_id", ""))))
		"text_read":
			_assert_player_fact("text_read(player, %s)" % _sanitize(str(event.get("text_id", ""))))
		"sign_read":
			_assert_player_fact("sign_read(player, %s)" % _sanitize(str(event.get("sign_id", ""))))
		"object_examined":
			_assert_player_fact("object_examined(player, %s)" % _sanitize(str(event.get("object_name", ""))))
		"object_identified":
			_assert_player_fact("object_identified(player, %s)" % _sanitize(str(event.get("object_name", ""))))
		"object_pointed_and_named":
			_assert_player_fact("object_pointed_named(player, %s)" % _sanitize(str(event.get("object_name", ""))))
		"writing_submitted":
			_assert_player_fact("response_written(player, %s)" % str(event.get("word_count", 0)))
		"photo_taken":
			_assert_player_fact("photo_taken(player, %s)" % _sanitize(str(event.get("subject_name", ""))))
		"food_ordered":
			_assert_player_fact("food_ordered(player, %s)" % _sanitize(str(event.get("item_name", ""))))
		"price_haggled":
			_assert_player_fact("price_haggled(player, %s)" % _sanitize(str(event.get("item_name", ""))))
		"gift_given":
			var npc_id: String = _sanitize(str(event.get("npc_id", "")))
			var item_name: String = _sanitize(str(event.get("item_name", "")))
			_assert_player_fact("gift_given(player, %s, %s)" % [npc_id, item_name])
		"translation_attempt":
			var correct: bool = event.get("correct", false)
			if correct:
				_assert_player_fact("translation_completed(player, correct)")
		"pronunciation_attempt":
			var phrase: String = _sanitize(str(event.get("phrase", "")))
			var score: int = int(event.get("score", 0))
			var timestamp: String = str(event.get("timestamp", 0))
			_assert_player_fact("pronunciation_score(player, %s, %s, %s)" % [phrase, str(score), timestamp])
			if event.get("passed", false):
				_assert_player_fact("pronunciation_passed(player, %s)" % phrase)
		"reading_completed":
			_assert_player_fact("text_read(player, %s)" % _sanitize(str(event.get("text_id", ""))))
		"questions_answered":
			_assert_player_fact("comprehension_done(player, %s)" % _sanitize(str(event.get("text_id", ""))))
		"conversation_turn", "conversation_turn_counted":
			var npc_id: String = _sanitize(str(event.get("npc_id", "")))
			var total: int = int(event.get("total", event.get("turn_count", 0)))
			_retract_player_fact_by_pattern("npc_conversation_turns", "player", npc_id)
			_assert_player_fact("npc_conversation_turns(player, %s, %s)" % [npc_id, str(total)])
		"physical_action_completed":
			_assert_player_fact("physical_action_done(player, %s)" % _sanitize(str(event.get("action_type", ""))))
		"npc_exam_completed":
			var exam_id: String = _sanitize(str(event.get("exam_id", "")))
			var score: int = int(event.get("score", 0))
			var max_points: int = int(event.get("max_points", 0))
			var cefr_level: String = _sanitize(str(event.get("cefr_level", "")))
			var timestamp: String = str(event.get("timestamp", 0))
			_assert_player_fact("assessment_result(player, %s, %s, %s, %s, %s)" % [exam_id, str(score), str(max_points), cefr_level, timestamp])
			_retract_player_fact_by_pattern("player_cefr_level", "player")
			_assert_player_fact("player_cefr_level(player, %s)" % cefr_level)
		_:
			return  # No re-evaluation for unhandled events
	_reevaluate_quests()

# ---------------------------------------------------------------------------
# Quest tracking
# ---------------------------------------------------------------------------

## Set callback for objective completion events.
func set_on_objective_completed(callback: Callable) -> void:
	_on_objective_completed = callback


## Set callback for quest completion events.
func set_on_quest_completed(callback: Callable) -> void:
	_on_quest_completed = callback


## Register active quest IDs for automatic re-evaluation.
func set_active_quests(quest_ids: Array[String]) -> void:
	_active_quest_ids = quest_ids
	var stale_keys: Array = []
	for key in _completed_objectives:
		var quest_id: String = str(key).split(":")[0]
		if quest_id not in quest_ids:
			stale_keys.append(key)
	for key in stale_keys:
		_completed_objectives.erase(key)


## Re-evaluate all active quests; emit quest_completed for any now complete.
func _reevaluate_quests() -> void:
	for quest_id in _active_quest_ids:
		if _completed_quests.has(quest_id):
			continue
		if _on_objective_completed.is_valid():
			_check_objective_completion(quest_id)
		if is_quest_complete(quest_id, "player") and not _completed_quests.has(quest_id):
			_completed_quests[quest_id] = true
			quest_completed.emit(quest_id)
			if _on_quest_completed.is_valid():
				_on_quest_completed.call(quest_id)


## Check individual objective completion within a quest (real query).
func _check_objective_completion(quest_id: String) -> void:
	var sanitized_id: String = _sanitize(quest_id)
	for idx in _objective_indices(sanitized_id):
		var key: String = "%s:%d" % [quest_id, idx]
		if _completed_objectives.has(key):
			continue
		if _holds("objective_complete(player, %s, %d)" % [sanitized_id, idx]):
			_completed_objectives[key] = true
			_on_objective_completed.call(quest_id, idx)
			objective_completed.emit(quest_id, idx)


## Collect the objective indices declared for a quest via quest_objective/2.
func _objective_indices(sanitized_id: String) -> Array[int]:
	var out: Array[int] = []
	for s in _query_var("quest_objective(%s, Idx)" % sanitized_id, "Idx"):
		out.append(int(s))
	return out


## Reconcile quest and objective completion state.
func reconcile() -> Dictionary:
	var result: Dictionary = {"completed_quests": [], "completed_objectives": []}
	if not _initialized:
		return result
	for quest_id in _active_quest_ids:
		var sanitized_id: String = _sanitize(quest_id)
		for idx in _objective_indices(sanitized_id):
			if _holds("objective_complete(player, %s, %d)" % [sanitized_id, idx]):
				result["completed_objectives"].append({"quest_id": quest_id, "objective_index": idx})
		if is_quest_complete(quest_id, "player"):
			result["completed_quests"].append(quest_id)
	return result


## Get bonus rewards for a quest (real query on quest_bonus_reward/4).
func get_bonus_rewards(quest_id: String) -> Array:
	if not _initialized:
		return []
	var results: Array = []
	for sol in _query("quest_bonus_reward(player, %s, Type, Value)" % _sanitize(quest_id)):
		if sol is Dictionary:
			results.append({"type": str(sol.get("Type", "")), "value": int(sol.get("Value", 0))})
	return results

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

## Clear all state, disconnect event bus, and mark the engine as uninitialized.
func dispose() -> void:
	if _event_bus != null and _event_bus_handler.is_valid():
		if _event_bus.has_method("disconnect_any"):
			_event_bus.disconnect_any(_event_bus_handler)
	_event_bus = null
	_prolog = null
	_native_available = false
	_player_facts.clear()
	_active_quest_ids.clear()
	_item_quantities.clear()
	_completed_objectives.clear()
	_completed_quests.clear()
	_on_objective_completed = Callable()
	_on_quest_completed = Callable()
	_initialized = false
	print("[Insimul] PrologEngine disposed")

# ---------------------------------------------------------------------------
# Native engine bridge helpers
# ---------------------------------------------------------------------------

## Consult a Prolog program (clauses + directives) into the native KB.
func _consult(source: String) -> void:
	if not _native_available or _prolog == null:
		return
	if not _prolog.consult(source):
		push_warning("[Insimul] consult failed: %s" % str(_prolog.last_error()))


## Assert a single ground fact/clause into the native KB (adds trailing period).
func _assert(fact: String) -> void:
	if not _native_available or _prolog == null:
		return
	_prolog.assert_fact(_term(fact))


## Retract the first matching fact/clause from the native KB.
func _retract(fact: String) -> void:
	if not _native_available or _prolog == null:
		return
	_prolog.retract_fact(_term(fact))


## Retract every clause matching a term pattern (uses `_` for wildcard args).
func _retract_all(pattern_term: String) -> void:
	if not _native_available or _prolog == null:
		return
	var term: String = _term(pattern_term)
	var guard: int = 0
	while _prolog.retract_fact(term) and guard < 4096:
		guard += 1


## Run a goal, returning the raw Array[Dictionary] of solutions (strips trailing period).
func _query(goal: String) -> Array:
	if not _native_available or _prolog == null:
		return []
	var g: String = goal.strip_edges()
	if g.ends_with("."):
		g = g.substr(0, g.length() - 1)
	return _prolog.query(g)


## True if the goal has at least one solution.
func _holds(goal: String) -> bool:
	return _query(goal).size() > 0


## Collect the string binding of `var_name` across every solution of `goal`.
func _query_var(goal: String, var_name: String) -> Array[String]:
	var out: Array[String] = []
	for sol in _query(goal):
		if sol is Dictionary and sol.has(var_name):
			out.append(str(sol[var_name]))
	return out


## Ensure a fact/clause term ends with exactly one period (native assert/retract format).
func _term(fact: String) -> String:
	var t: String = fact.strip_edges()
	if not t.ends_with("."):
		t += "."
	return t

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Sanitize a string into a valid Prolog atom (lowercase, underscores only).
func _sanitize(text: String) -> String:
	var result: String = text.to_lower()
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]")
	result = regex.sub(result, "_", true)
	if not result.is_empty() and result[0].is_valid_int():
		result = "_" + result
	while result.contains("__"):
		result = result.replace("__", "_")
	result = result.trim_suffix("_")
	return result


## Escape backslashes and single quotes for Prolog quoted atoms.
func _escape(text: String) -> String:
	return text.replace("\\", "\\\\").replace("'", "\\'")

# ---------------------------------------------------------------------------
# Item quantity tracking
# ---------------------------------------------------------------------------

func _get_item_quantity(item_name: String) -> int:
	return int(_item_quantities.get(item_name, 0))


func _update_item_quantity(item_name: String, delta: int) -> void:
	var old_qty: int = _get_item_quantity(item_name)
	var new_qty: int = max(0, old_qty + delta)
	_item_quantities[item_name] = new_qty
	_retract_all("has_item(player, %s, _)" % item_name)
	if new_qty > 0:
		_assert("has_item(player, %s, %d)" % [item_name, new_qty])


## Assert taxonomy facts for an item (category, material, base_type, rarity, IS-A chain).
func _assert_item_taxonomy(item_name: String, taxonomy: Dictionary) -> void:
	if taxonomy.has("category") and not str(taxonomy["category"]).is_empty():
		_assert("item_category(%s, %s)" % [item_name, _sanitize(str(taxonomy["category"]))])
		_assert("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["category"]))])
	if taxonomy.has("material") and not str(taxonomy["material"]).is_empty():
		_assert("item_material(%s, %s)" % [item_name, _sanitize(str(taxonomy["material"]))])
	if taxonomy.has("base_type") and not str(taxonomy["base_type"]).is_empty():
		_assert("item_base_type(%s, %s)" % [item_name, _sanitize(str(taxonomy["base_type"]))])
		_assert("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["base_type"]))])
	elif taxonomy.has("baseType") and not str(taxonomy["baseType"]).is_empty():
		_assert("item_base_type(%s, %s)" % [item_name, _sanitize(str(taxonomy["baseType"]))])
		_assert("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["baseType"]))])
	if taxonomy.has("rarity") and not str(taxonomy["rarity"]).is_empty():
		_assert("item_rarity(%s, %s)" % [item_name, _sanitize(str(taxonomy["rarity"]))])
	if taxonomy.has("item_type") and not str(taxonomy["item_type"]).is_empty():
		_assert("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["item_type"]))])
	elif taxonomy.has("itemType") and not str(taxonomy["itemType"]).is_empty():
		_assert("item_is_a(%s, %s)" % [item_name, _sanitize(str(taxonomy["itemType"]))])
