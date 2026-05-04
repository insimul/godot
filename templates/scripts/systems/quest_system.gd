extends Node
## Quest System — autoloaded singleton.
## Ported from Insimul's QuestObjectManager + QuestCompletionEngine.

signal quest_accepted(quest_id: String)
signal quest_completed(quest_id: String)
signal objective_completed(quest_id: String, objective_id: String)
signal quest_item_collected(quest_id: String, objective_id: String, item_name: String)

## Scavenger hunt categories for vocabulary rotation.
const SCAVENGER_CATEGORIES: Array[String] = [
	"food", "colors", "animals", "clothing", "household",
	"nature", "body", "professions", "transportation", "weather"
]

var all_quests: Array[Dictionary] = []
var active_quest_ids: Array[String] = []
var completed_quest_ids: Array[String] = []
var objectives: Array[Dictionary] = []
var _game_time: float = 0.0

## Optional callback to test whether a world XZ point is inside a building footprint.
## Signature: func(x: float, z: float) -> bool
var _point_in_building_check: Callable = Callable()

## Quest-action mapping catalog (built at _ready).
var _action_mappings: Array[Dictionary] = []


func _ready() -> void:
	_build_action_mapping_catalog()


func _process(delta: float) -> void:
	_game_time += delta


# ── Action mapping catalog ───────────────────────────────────────────────

func _build_action_mapping_catalog() -> void:
	_action_mappings = [
		{
			"objective_type": "collect_item", "event_type": "item_collected",
			"match_fields": [{ "event_field": "item_name", "objective_field": "item_name", "comparison": "contains_lower", "optional": true }],
			"has_quantity": true, "quantity": { "current_field": "collected_count", "required_field": "item_count", "default_required": 1 },
		},
		{
			"objective_type": "visit_location", "event_type": "location_visited",
			"match_fields": [{ "event_field": "location_name", "objective_field": "location_name", "comparison": "contains_lower", "optional": true }],
		},
		{
			"objective_type": "discover_location", "event_type": "location_discovered",
			"match_fields": [{ "event_field": "location_name", "objective_field": "location_name", "comparison": "contains_lower", "optional": true }],
		},
		{
			"objective_type": "talk_to_npc", "event_type": "npc_talked",
			"match_fields": [{ "event_field": "npc_id", "objective_field": "npc_id", "comparison": "exact", "optional": true }],
		},
		{
			"objective_type": "photograph_subject", "event_type": "photo_taken",
			"match_fields": [
				{ "event_field": "subject_name", "objective_field": "target_subject", "comparison": "contains_lower", "optional": true },
				{ "event_field": "subject_category", "objective_field": "target_category", "comparison": "exact", "optional": true },
			],
			"has_quantity": true, "quantity": { "current_field": "current_count", "required_field": "required_count", "default_required": 1 },
		},
		{
			"objective_type": "photograph_activity", "event_type": "photo_taken",
			"match_fields": [
				{ "event_field": "subject_name", "objective_field": "target_subject", "comparison": "contains_lower", "optional": true },
				{ "event_field": "subject_category", "objective_field": "target_category", "comparison": "exact", "optional": true },
			],
			"has_quantity": true, "quantity": { "current_field": "current_count", "required_field": "required_count", "default_required": 1 },
		},
		{
			"objective_type": "physical_action", "event_type": "physical_action_completed",
			"match_fields": [{ "event_field": "action_type", "objective_field": "action_type", "comparison": "exact", "optional": true }],
			"has_quantity": true, "quantity": { "current_field": "actions_completed", "required_field": "actions_required", "default_required": 1 },
		},
		{
			"objective_type": "craft_item", "event_type": "item_crafted",
			"match_fields": [{ "event_field": "item_name", "objective_field": "item_name", "comparison": "contains_lower", "optional": true }],
			"has_quantity": true, "quantity": { "current_field": "crafted_count", "required_field": "required_count", "default_required": 1 },
		},
		{
			"objective_type": "buy_item", "event_type": "item_purchased",
			"match_fields": [{ "event_field": "item_name", "objective_field": "item_name", "comparison": "contains_lower", "optional": true }],
			"has_quantity": true, "quantity": { "current_field": "current_count", "required_field": "required_count", "default_required": 1 },
		},
	]


# ── Internal helpers ─────────────────────────────────────────────────────

## Check if an objective is locked due to unmet dependencies/ordering.
func _is_objective_locked(obj: Dictionary) -> bool:
	# Check explicit depends_on
	var depends_on: Array = obj.get("depends_on", [])
	if depends_on.size() > 0:
		for dep_id in depends_on:
			for other in objectives:
				if other.get("id") == dep_id and not other.get("completed", false):
					return true

	# Check order-based sequencing
	var obj_order: int = obj.get("order", -1)
	if obj_order >= 0:
		var obj_quest_id: String = obj.get("quest_id", "")
		for other in objectives:
			if other.get("id") == obj.get("id"):
				continue
			if other.get("quest_id", "") != obj_quest_id:
				continue
			var other_order: int = other.get("order", -1)
			if other_order >= 0 and other_order < obj_order and not other.get("completed", false):
				return true

	return false


## Iterate over eligible (unlocked, incomplete, type-matched) objectives.
## types can be a single string or an Array of strings.
func _for_each_objective(quest_id: String, types, callback: Callable) -> void:
	var type_list: Array
	if types is String:
		type_list = [types]
	else:
		type_list = types

	# Snapshot eligible objectives before iteration
	var eligible: Array[Dictionary] = []
	for obj in objectives:
		if obj.get("completed", false):
			continue
		if not quest_id.is_empty() and obj.get("quest_id") != quest_id:
			continue
		if obj.get("type", "") not in type_list:
			continue
		if _is_objective_locked(obj):
			continue
		eligible.append(obj)

	for obj in eligible:
		if obj.get("completed", false):
			continue  # re-check
		callback.call(obj)


# ── Data loading ─────────────────────────────────────────────────────────

func load_from_data(world_data: Dictionary) -> void:
	var systems: Dictionary = world_data.get("systems", {})
	all_quests.assign(systems.get("quests", []))
	print("[Insimul] QuestSystem loaded %d quests" % all_quests.size())


func get_quest(quest_id: String) -> Dictionary:
	for q in all_quests:
		if q.get("id", "") == quest_id:
			return q
	return {}


# ── Quest management ────────────────────────────────────────────────────

func accept_quest(quest_id: String) -> bool:
	if quest_id in active_quest_ids:
		return false
	var quest := get_quest(quest_id)
	if quest.is_empty():
		return false
	active_quest_ids.append(quest_id)
	quest_accepted.emit(quest_id)
	print("[Insimul] Quest accepted: %s" % quest.get("title", quest_id))
	return true


func complete_quest(quest_id: String) -> bool:
	if quest_id not in active_quest_ids:
		return false
	active_quest_ids.erase(quest_id)
	completed_quest_ids.append(quest_id)
	quest_completed.emit(quest_id)
	print("[Insimul] Quest completed: %s" % quest_id)
	return true


func complete_objective(quest_id: String, objective_id: String) -> bool:
	for obj in objectives:
		if obj.get("quest_id") == quest_id and obj.get("id") == objective_id:
			if obj.get("completed", false):
				return false
			if _is_objective_locked(obj):
				return false
			obj["completed"] = true
			objective_completed.emit(quest_id, objective_id)
			print("[Insimul] Objective completed: %s/%s" % [quest_id, objective_id])

			# Check if all objectives for this quest are complete
			if is_quest_complete(quest_id):
				quest_completed.emit(quest_id)
			return true
	return false


## Check if a specific objective is complete.
func is_objective_complete(quest_id: String, objective_id: String) -> bool:
	for obj in objectives:
		if obj.get("quest_id") == quest_id and obj.get("id") == objective_id:
			return obj.get("completed", false)
	return false


## Check if all objectives for a quest are complete.
func is_quest_complete(quest_id: String) -> bool:
	var has_objectives := false
	for obj in objectives:
		if obj.get("quest_id") != quest_id:
			continue
		has_objectives = true
		if not obj.get("completed", false):
			return false
	return has_objectives


## Get all unlocked, incomplete objectives for a quest.
func get_available_objectives(quest_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obj in objectives:
		if obj.get("quest_id") != quest_id:
			continue
		if not obj.get("completed", false) and not _is_objective_locked(obj):
			result.append(obj)
	return result


## Get all locked (dependencies not met) objectives for a quest.
func get_locked_objectives(quest_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obj in objectives:
		if obj.get("quest_id") != quest_id:
			continue
		if not obj.get("completed", false) and _is_objective_locked(obj):
			result.append(obj)
	return result


# ── Timed objectives ────────────────────────────────────────────────────

## Check timed objectives and return descriptions of any that expired.
func check_timed_objectives() -> Array[String]:
	var expired: Array[String] = []
	for obj in objectives:
		if obj.get("completed", false):
			continue
		var limit: float = obj.get("time_limit_seconds", 0.0)
		var started: float = obj.get("started_at", -1.0)
		if limit <= 0.0 or started < 0.0:
			continue

		var elapsed := _game_time - started
		if elapsed > limit:
			obj["completed"] = true
			expired.append("Time expired: %s" % obj.get("description", ""))
			print("[Insimul] Timed objective expired: %s" % obj.get("id", ""))
	return expired


## Get remaining seconds for a timed objective, or -1 if untimed.
func get_objective_time_remaining(objective_id: String) -> float:
	for obj in objectives:
		if obj.get("id") == objective_id:
			var limit: float = obj.get("time_limit_seconds", 0.0)
			var started: float = obj.get("started_at", -1.0)
			if limit > 0.0 and started >= 0.0:
				var elapsed := _game_time - started
				return maxf(0.0, limit - elapsed)
	return -1.0


## Request a GPS-style waypoint hint. Returns English hint text or empty string.
func request_navigation_hint(quest_id: String = "") -> String:
	for obj in objectives:
		if obj.get("completed", false):
			continue
		if not quest_id.is_empty() and obj.get("quest_id") != quest_id:
			continue
		var obj_type: String = obj.get("type", "")
		if obj_type != "navigate_language" and obj_type != "follow_directions":
			continue

		obj["hints_requested"] = obj.get("hints_requested", 0) + 1
		obj["show_waypoint"] = true
		print("[Insimul] Navigation hint #%d for %s" % [obj["hints_requested"], obj.get("id", "")])
		return obj.get("description", "")
	return ""


## Get next scavenger hunt category (round-robin).
static func get_next_scavenger_category(last_category_index: int) -> String:
	var next := (last_category_index + 1) % SCAVENGER_CATEGORIES.size()
	return SCAVENGER_CATEGORIES[next]


# ── NPC / conversation tracking ─────────────────────────────────────────

## Track NPC conversation for talk_to_npc objectives.
func track_npc_conversation(npc_id: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "talk_to_npc", func(obj: Dictionary) -> void:
		if obj.get("npc_id", "") == npc_id:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track vocabulary usage for use_vocabulary / collect_vocabulary objectives.
func track_vocabulary_usage(word: String, quest_id: String = "") -> void:
	var lower_word := word.to_lower()

	_for_each_objective(quest_id, ["use_vocabulary", "collect_vocabulary"], func(obj: Dictionary) -> void:
		# If targetWords specified, only count matching words
		var target_words: Array = obj.get("target_words", [])
		if target_words.size() > 0 and lower_word not in target_words:
			return

		# Don't double-count the same word
		var words_used: Array = obj.get("words_used", [])
		if lower_word in words_used:
			return

		words_used.append(lower_word)
		obj["words_used"] = words_used
		obj["current_count"] = obj.get("current_count", 0) + 1

		var required: int = obj.get("required_count", 10)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a conversation turn for complete_conversation objectives.
func track_conversation_turn(keywords: Array[String] = [], quest_id: String = "") -> void:
	_for_each_objective(quest_id, "complete_conversation", func(obj: Dictionary) -> void:
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 5)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track NPC-initiated conversation acceptance for conversation_initiation objectives.
func track_conversation_initiation(npc_id: String, accepted: bool, response_quality: float = 100.0, quest_id: String = "") -> void:
	if not accepted:
		return

	_for_each_objective(quest_id, "conversation_initiation", func(obj: Dictionary) -> void:
		if not obj.get("npc_id", "").is_empty() and obj.get("npc_id") != npc_id:
			return

		obj["current_count"] = obj.get("current_count", 0) + 1
		obj["response_quality"] = response_quality

		var min_quality: float = obj.get("min_response_quality", 0.0)
		var meets_quality: bool = response_quality >= min_quality

		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required and meets_quality:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track topic-based NPC conversation turns for objectives like
## ask_for_directions, order_food, haggle_price, introduce_self, build_friendship.
func track_npc_conversation_turn(npc_id: String, topic_tag: String = "", quest_id: String = "") -> void:
	var TAG_TO_TYPES: Dictionary = {
		"directions": ["ask_for_directions"],
		"order": ["order_food"],
		"haggle": ["haggle_price"],
		"introduction": ["introduce_self"],
		"friendship": ["build_friendship"],
	}
	var target_types: Array[String] = []
	if not topic_tag.is_empty() and TAG_TO_TYPES.has(topic_tag):
		target_types = TAG_TO_TYPES[topic_tag]
	else:
		target_types = ["ask_for_directions", "order_food", "haggle_price", "introduce_self", "build_friendship"]

	_for_each_objective(quest_id, target_types, func(obj: Dictionary) -> void:
		if not obj.get("npc_id", "").is_empty() and obj.get("npc_id") != npc_id:
			return

		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track accumulated conversation turns for arrival_conversation objectives.
func track_conversation_turn_counted(npc_id: String, total_turns: int, meaningful_turns: int, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "arrival_conversation", func(obj: Dictionary) -> void:
		if not obj.get("npc_id", "").is_empty() and obj.get("npc_id") != npc_id:
			return
		obj["current_count"] = meaningful_turns
		var required: int = obj.get("required_count", 3)
		if meaningful_turns >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a detected conversational action against matching objectives.
func track_conversational_action(action: String, npc_id: String, topic: String = "", quest_id: String = "") -> void:
	var ACTION_TO_TYPES: Dictionary = {
		"asked_about_topic": ["asked_about_topic"],
		"used_target_language": ["used_target_language", "arrival_writing"],
		"answered_question": ["answered_question"],
		"requested_information": ["requested_information", "ask_for_directions"],
		"made_introduction": ["made_introduction", "introduce_self"],
	}
	var target_types: Array = ACTION_TO_TYPES.get(action, [action])

	_for_each_objective(quest_id, target_types, func(obj: Dictionary) -> void:
		if not obj.get("npc_id", "").is_empty() and obj.get("npc_id") != npc_id:
			return

		# For topic-based objectives, check topic match
		if obj.get("type", "") == "asked_about_topic":
			var obj_target_words: Array = obj.get("target_words", [])
			if obj_target_words.size() > 0:
				if not topic.is_empty() and topic not in obj_target_words:
					return

		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)

	# Also fire arrival_initiate_conversation for any conversational action
	_for_each_objective(quest_id, "arrival_initiate_conversation", func(obj: Dictionary) -> void:
		if not obj.get("npc_id", "").is_empty() and obj.get("npc_id") != npc_id:
			return
		complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Pronunciation ────────────────────────────────────────────────────────

## Track a pronunciation attempt for pronunciation_check / listen_and_repeat / speak_phrase objectives.
## score: pronunciation accuracy score (0-100)
func track_pronunciation_attempt(passed: bool, score: float = 0.0, phrase: String = "", quest_id: String = "") -> void:
	_for_each_objective(quest_id, ["pronunciation_check", "listen_and_repeat", "speak_phrase"], func(obj: Dictionary) -> void:
		# Store pronunciation score data
		if score > 0.0:
			var scores: Array = obj.get("pronunciation_scores", [])
			scores.append(score)
			obj["pronunciation_scores"] = scores
			if score > obj.get("pronunciation_best_score", 0.0):
				obj["pronunciation_best_score"] = score

		if passed:
			obj["current_count"] = obj.get("current_count", 0) + 1
			var required: int = obj.get("required_count", 3)
			if obj["current_count"] >= required:
				# If min_average_score is set, check average before completing
				var min_avg: float = obj.get("min_average_score", 0.0)
				var all_scores: Array = obj.get("pronunciation_scores", [])
				if min_avg > 0.0 and all_scores.size() > 0:
					var sum := 0.0
					for s in all_scores:
						sum += s
					var avg := sum / all_scores.size()
					if avg >= min_avg:
						complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
				else:
					complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Get pronunciation statistics for an objective.
func get_pronunciation_stats(quest_id: String, objective_id: String) -> Dictionary:
	for obj in objectives:
		if obj.get("quest_id") == quest_id and obj.get("id") == objective_id and obj.get("type") == "pronunciation_check":
			var scores: Array = obj.get("pronunciation_scores", [])
			var avg := 0.0
			if scores.size() > 0:
				var sum := 0.0
				for s in scores:
					sum += s
				avg = sum / scores.size()
			return { "scores": scores, "average": avg, "passed": scores.size(), "valid": true }
	return { "valid": false }


## Reveal the next pronunciation hint. Returns the hint text, or empty string
## when no more hints are available. Each revealed hint applies its score
## penalty (stored in obj.hint_score_penalties) to subsequent attempts.
func reveal_pronunciation_hint(quest_id: String, objective_id: String) -> String:
	for obj in objectives:
		if obj.get("quest_id") != quest_id or obj.get("id") != objective_id:
			continue
		var hint_texts: Array = obj.get("hint_texts", [])
		var revealed: int = obj.get("hints_revealed", 0)
		if revealed >= hint_texts.size():
			return ""
		var hint: String = hint_texts[revealed]
		obj["hints_revealed"] = revealed + 1
		return hint
	return ""


# ── Romance ──────────────────────────────────────────────────────────────

const ROMANCE_STAGE_ORDER: Array[String] = [
	"none", "attracted", "flirting", "dating", "committed", "engaged", "married"
]

## Complete romance_stage_reach objectives whose target stage has been met.
func track_romance_stage_reach(current_stage: String, quest_id: String = "") -> void:
	var current_idx: int = ROMANCE_STAGE_ORDER.find(current_stage.to_lower())
	if current_idx < 0:
		return

	_for_each_objective(quest_id, "romance_stage_reach", func(obj: Dictionary) -> void:
		var target: String = obj.get("target_romance_stage", "")
		if target.is_empty():
			target = obj.get("target_phrase", "")
		target = target.to_lower()
		var target_idx: int = ROMANCE_STAGE_ORDER.find(target)
		if target_idx < 0:
			return
		if current_idx >= target_idx:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Complete romance_gift objectives when the player gifts a romance target.
func track_romance_gift(npc_id: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "romance_gift", func(obj: Dictionary) -> void:
		var recipient: String = obj.get("romance_gift_recipient_npc_id", "")
		if not recipient.is_empty() and recipient != npc_id:
			return
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Writing ──────────────────────────────────────────────────────────────

## Track a writing submission for write_response / describe_scene / arrival_writing objectives.
func track_writing_submission(text: String, word_count: int, quest_id: String = "") -> void:
	# Complete arrival_writing objectives with word count validation
	_for_each_objective(quest_id, "arrival_writing", func(obj: Dictionary) -> void:
		var min_words: int = obj.get("min_word_count", 20)
		if word_count >= min_words:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)

	_for_each_objective(quest_id, ["write_response", "describe_scene"], func(obj: Dictionary) -> void:
		var responses: Array = obj.get("written_responses", [])
		responses.append(text)
		obj["written_responses"] = responses
		obj["current_count"] = obj.get("current_count", 0) + 1

		# Reject submissions below minimum word count
		var min_words: int = obj.get("min_word_count", 0)
		if min_words > 0 and word_count < min_words:
			return

		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Item tracking ────────────────────────────────────────────────────────

## Track item delivery to an NPC for deliver_item objectives.
func track_item_delivery(npc_id: String, player_item_names: Array, quest_id: String = "") -> void:
	var normalized_items: Array = []
	for item_name in player_item_names:
		normalized_items.append(item_name.to_lower())

	_for_each_objective(quest_id, "deliver_item", func(obj: Dictionary) -> void:
		var obj_npc: String = obj.get("npc_id", "")
		if not obj_npc.is_empty() and obj_npc != npc_id:
			return
		var obj_item: String = obj.get("item_name", "").to_lower()
		if not obj_item.is_empty() and normalized_items.has(obj_item):
			obj["delivered"] = true
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Check inventory items against collect_item / collect_items objectives.
func check_inventory_objectives(player_item_names: Array, quest_id: String = "") -> void:
	var normalized_items: Array = []
	for item_name in player_item_names:
		normalized_items.append(item_name.to_lower())

	_for_each_objective(quest_id, ["collect_item", "collect_items"], func(obj: Dictionary) -> void:
		var obj_name: String = obj.get("item_name", "").to_lower()
		if obj_name.is_empty():
			return

		var matched := false
		for n in normalized_items:
			if n == obj_name or n.contains(obj_name) or obj_name.contains(n):
				matched = true
				break
		if matched:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a crafted item for craft_item objectives.
func track_item_crafted(item_id: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "craft_item", func(obj: Dictionary) -> void:
		if obj.get("crafted_item_id", "") == item_id or obj.get("item_name", "") == item_id:
			obj["crafted_count"] = obj.get("crafted_count", 0) + 1
			var required: int = obj.get("required_count", 1)
			if obj["crafted_count"] >= required:
				complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a gift given to an NPC for give_gift objectives.
func track_gift_given(npc_id: String, item_name: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "give_gift", func(obj: Dictionary) -> void:
		var obj_npc: String = obj.get("npc_id", "")
		if not obj_npc.is_empty() and obj_npc != npc_id:
			return
		complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a collected item by name for collect_item objectives.
## Supports exact, partial, category, and word-overlap matching.
## Returns Array of match dictionaries with quest_id, objective_id, matched_name, collected_count, required_count, completed.
func track_collected_item_by_name(item_name: String, category: String = "", quest_id: String = "") -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var lower_item := item_name.to_lower()
	var lower_cat := category.to_lower()

	_for_each_objective(quest_id, "collect_item", func(obj: Dictionary) -> void:
		var obj_item: String = obj.get("item_name", "").to_lower()
		var name_match := false

		# Exact match
		if not obj_item.is_empty() and obj_item == lower_item:
			name_match = true
		# Partial match: item name contains objective name or vice versa
		elif not obj_item.is_empty() and (lower_item.contains(obj_item) or obj_item.contains(lower_item)):
			name_match = true
		# Category match
		elif not lower_cat.is_empty() and not obj.get("vocabulary_category", "").is_empty() and obj.get("vocabulary_category", "").to_lower() == lower_cat:
			name_match = true
		# Word-overlap matching
		elif not obj_item.is_empty():
			var obj_words: PackedStringArray = obj_item.split(" ")
			var key_words: PackedStringArray = lower_item.split(" ")
			for w in obj_words:
				if w.length() >= 3 and w in key_words:
					name_match = true
					break
			if not name_match:
				for w in key_words:
					if w.length() >= 3 and w in obj_words:
						name_match = true
						break
		# No item name on objective means any item counts
		elif obj_item.is_empty() and obj.get("vocabulary_category", "").is_empty():
			name_match = true

		if not name_match:
			return

		var required: int = obj.get("item_count", 1)
		if required <= 0:
			required = 1
		obj["collected_count"] = obj.get("collected_count", 0) + 1

		var is_completed: bool = obj["collected_count"] >= required
		if is_completed:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))

		matches.append({
			"quest_id": obj.get("quest_id", ""),
			"objective_id": obj.get("id", ""),
			"matched_name": item_name,
			"collected_count": obj["collected_count"],
			"required_count": required,
			"completed": is_completed,
		})

		quest_item_collected.emit(obj.get("quest_id", ""), obj.get("id", ""), item_name)
	)

	return matches


# ── Combat / reputation ──────────────────────────────────────────────────

## Track an enemy defeat for defeat_enemies objectives.
func track_enemy_defeated(enemy_type: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "defeat_enemies", func(obj: Dictionary) -> void:
		var obj_enemy: String = obj.get("enemy_type", "")
		if not obj_enemy.is_empty() and obj_enemy != enemy_type:
			return
		obj["enemies_defeated"] = obj.get("enemies_defeated", 0) + 1
		var required: int = obj.get("enemies_required", 1)
		if obj["enemies_defeated"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track reputation gain for gain_reputation objectives.
func track_reputation_gain(faction_id: String, amount: int, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "gain_reputation", func(obj: Dictionary) -> void:
		if obj.get("faction_id", "") != faction_id:
			return
		obj["reputation_gained"] = obj.get("reputation_gained", 0) + amount
		var required: int = obj.get("reputation_required", 100)
		if obj["reputation_gained"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track escort/delivery arrival for escort_npc / deliver_item objectives.
func track_arrival(npc_or_item_id: String, reached: bool, quest_id: String = "") -> void:
	if not reached:
		return
	_for_each_objective(quest_id, ["escort_npc", "deliver_item"], func(obj: Dictionary) -> void:
		if obj.get("type", "") == "escort_npc":
			obj["arrived"] = true
		else:
			obj["delivered"] = true
		complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Location tracking ────────────────────────────────────────────────────

## Track location visit/discovery for visit_location / discover_location objectives.
func track_location_visit(location_id: String, location_name: String, quest_id: String = "") -> void:
	var lower_name := location_name.to_lower()
	var lower_id := location_id.to_lower()

	_for_each_objective(quest_id, ["visit_location", "discover_location"], func(obj: Dictionary) -> void:
		var obj_name: String = obj.get("location_name", "").to_lower()
		if obj_name.is_empty():
			return
		if obj_name == lower_id or obj_name == lower_name or lower_name.contains(obj_name) or obj_name.contains(lower_name):
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Teaching ─────────────────────────────────────────────────────────────

## Track teaching a vocabulary word to an NPC for teach_vocabulary objectives.
func track_teach_word(npc_id: String, word: String, quest_id: String = "") -> void:
	var lower_word: String = word.to_lower()
	_for_each_objective(quest_id, "teach_vocabulary", func(obj: Dictionary) -> void:
		if not obj.get("npc_id", "").is_empty() and obj.get("npc_id") != npc_id:
			return

		var words_taught: Array = obj.get("words_taught", [])
		if lower_word in words_taught:
			return
		words_taught.append(lower_word)
		obj["words_taught"] = words_taught
		obj["current_count"] = obj.get("current_count", 0) + 1

		var required: int = obj.get("required_count", 3)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track teaching a phrase to an NPC for teach_phrase objectives.
func track_teach_phrase(npc_id: String, phrase: String, quest_id: String = "") -> void:
	var lower_phrase: String = phrase.to_lower()
	_for_each_objective(quest_id, "teach_phrase", func(obj: Dictionary) -> void:
		if not obj.get("npc_id", "").is_empty() and obj.get("npc_id") != npc_id:
			return

		var phrases_taught: Array = obj.get("phrases_taught", [])
		if lower_phrase in phrases_taught:
			return
		phrases_taught.append(lower_phrase)
		obj["phrases_taught"] = phrases_taught
		obj["current_count"] = obj.get("current_count", 0) + 1

		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Mercantile ───────────────────────────────────────────────────────────

## Track food ordering at a merchant for order_food objectives.
func track_food_ordered(item_name: String, merchant_id: String, business_type: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "order_food", func(obj: Dictionary) -> void:
		if not obj.get("merchant_id", "").is_empty() and obj.get("merchant_id") != merchant_id:
			return

		var items_purchased: Array = obj.get("items_purchased", [])
		items_purchased.append(item_name)
		obj["items_purchased"] = items_purchased
		obj["current_count"] = obj.get("current_count", 0) + 1

		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track price haggling in target language for haggle_price objectives.
func track_price_haggled(item_name: String, merchant_id: String, typed_word: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "haggle_price", func(obj: Dictionary) -> void:
		if not obj.get("merchant_id", "").is_empty() and obj.get("merchant_id") != merchant_id:
			return

		obj["current_count"] = obj.get("current_count", 0) + 1

		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Direction / navigation ───────────────────────────────────────────────

## Track a direction step completed for follow_directions objectives.
func track_direction_step(quest_id: String = "") -> void:
	_for_each_objective(quest_id, "follow_directions", func(obj: Dictionary) -> void:
		obj["steps_completed"] = obj.get("steps_completed", 0) + 1
		obj["current_count"] = obj["steps_completed"]

		var steps_req: int = obj.get("steps_required", 0)
		var required: int = steps_req if steps_req > 0 else obj.get("required_count", 1)
		if obj["steps_completed"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a navigation waypoint reached for navigate_language objectives.
func track_navigation_waypoint(quest_id: String = "") -> void:
	_for_each_objective(quest_id, "navigate_language", func(obj: Dictionary) -> void:
		obj["waypoints_reached"] = obj.get("waypoints_reached", 0) + 1
		obj["steps_completed"] = obj["waypoints_reached"]

		var required: int = obj.get("steps_required", 1)
		if obj["waypoints_reached"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Check if player is near a direction/navigation waypoint.
## Call this from _physics_process with the player's position.
func check_direction_proximity(player_pos: Vector3) -> void:
	for obj in objectives:
		if obj.get("completed", false):
			continue
		if _is_objective_locked(obj):
			continue
		var obj_type: String = obj.get("type", "")

		if obj_type == "follow_directions":
			var steps: Array = obj.get("direction_steps", [])
			var step_idx: int = obj.get("steps_completed", 0)
			if step_idx >= steps.size():
				continue
			var step: Dictionary = steps[step_idx]
			var target: Dictionary = step.get("target_position", {})
			if target.is_empty():
				continue
			var target_vec := Vector3(target.get("x", 0.0), player_pos.y, target.get("z", 0.0))
			var radius: float = obj.get("step_radius", 6.0)
			if player_pos.distance_to(target_vec) <= radius:
				obj["steps_completed"] = step_idx + 1
				obj["current_count"] = obj["steps_completed"]
				var steps_required: int = obj.get("steps_required", steps.size())
				if obj["steps_completed"] >= steps_required:
					complete_objective(obj.get("quest_id", ""), obj.get("id", ""))

		elif obj_type == "navigate_language":
			var waypoints: Array = obj.get("navigation_waypoints", [])
			var wp_idx: int = obj.get("waypoints_reached", 0)
			if wp_idx >= waypoints.size():
				continue
			var wp: Dictionary = waypoints[wp_idx]
			var target: Dictionary = wp.get("target_position", {})
			if target.is_empty():
				continue
			var target_vec := Vector3(target.get("x", 0.0), player_pos.y, target.get("z", 0.0))
			var radius: float = obj.get("step_radius", 6.0)
			if player_pos.distance_to(target_vec) <= radius:
				obj["waypoints_reached"] = wp_idx + 1
				obj["steps_completed"] = obj["waypoints_reached"]
				if obj["waypoints_reached"] >= waypoints.size():
					complete_objective(obj.get("quest_id", ""), obj.get("id", ""))


# ── Listening / translation ──────────────────────────────────────────────

## Track a listening comprehension answer for listening_comprehension objectives.
func track_listening_answer(correct: bool, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "listening_comprehension", func(obj: Dictionary) -> void:
		obj["questions_answered"] = obj.get("questions_answered", 0) + 1
		if correct:
			obj["questions_correct"] = obj.get("questions_correct", 0) + 1
		obj["current_count"] = obj["questions_answered"]

		var required: int = obj.get("required_count", 3)
		if obj.get("questions_correct", 0) >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a translation attempt for translation_challenge objectives.
func track_translation_attempt(correct: bool, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "translation_challenge", func(obj: Dictionary) -> void:
		if correct:
			obj["translations_correct"] = obj.get("translations_correct", 0) + 1
		obj["translations_completed"] = obj.get("translations_completed", 0) + 1
		obj["current_count"] = obj.get("translations_correct", 0)

		var required: int = obj.get("required_count", 3)
		if obj.get("translations_correct", 0) >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Object interaction ───────────────────────────────────────────────────

## Track an object identified for identify_object objectives.
func track_object_identified(object_name: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "identify_object", func(obj: Dictionary) -> void:
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track an object examined for examine_object objectives.
func track_object_examined(object_name: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "examine_object", func(obj: Dictionary) -> void:
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a sign read for read_sign objectives.
func track_sign_read(sign_id: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "read_sign", func(obj: Dictionary) -> void:
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track point-and-name for point_and_name objectives.
func track_point_and_name(object_name: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "point_and_name", func(obj: Dictionary) -> void:
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Text / reading / comprehension ──────────────────────────────────────

## Track a text found for find_text objectives.
func track_text_found(text_id: String, text_name: String, quest_id: String = "") -> void:
	var lower_name := text_name.to_lower()
	_for_each_objective(quest_id, "find_text", func(obj: Dictionary) -> void:
		var target_name: String = obj.get("item_name", "").to_lower()
		if not target_name.is_empty() and target_name != lower_name and target_name != text_id:
			return
		var texts_found: Array = obj.get("texts_found", [])
		if text_id in texts_found:
			return
		texts_found.append(text_id)
		obj["texts_found"] = texts_found
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a text read for read_text objectives.
func track_text_read(text_id: String, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "read_text", func(obj: Dictionary) -> void:
		if not obj.get("text_id", "").is_empty() and obj.get("text_id") != text_id:
			return
		var texts_read: Array = obj.get("texts_read", [])
		if text_id in texts_read:
			return
		texts_read.append(text_id)
		obj["texts_read"] = texts_read
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track a comprehension quiz answer for comprehension_quiz objectives.
func track_comprehension_answer(correct: bool, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "comprehension_quiz", func(obj: Dictionary) -> void:
		obj["quiz_answered"] = obj.get("quiz_answered", 0) + 1
		if correct:
			obj["quiz_correct"] = obj.get("quiz_correct", 0) + 1
		obj["current_count"] = obj.get("quiz_correct", 0)

		var required: int = obj.get("required_count", 3)
		var threshold: int = obj.get("quiz_pass_threshold", required)
		if obj.get("quiz_correct", 0) >= threshold:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Photography / observation ────────────────────────────────────────────

## Track a photo taken for photograph_subject objectives.
func track_photo_taken(subject_name: String, subject_category: String, subject_activity: String = "", quest_id: String = "") -> void:
	var lower_name := subject_name.to_lower()
	var lower_activity := subject_activity.to_lower()

	_for_each_objective(quest_id, "photograph_subject", func(obj: Dictionary) -> void:
		if not obj.get("target_category", "").is_empty() and obj.get("target_category") != subject_category:
			return
		if not obj.get("target_subject", "").is_empty() and obj.get("target_subject", "").to_lower() != lower_name:
			return
		if not obj.get("target_activity", "").is_empty():
			if lower_activity.is_empty():
				return
			if not lower_activity.contains(obj.get("target_activity", "").to_lower()):
				return

		var tracking_key: String = lower_name + ":" + lower_activity if not obj.get("target_activity", "").is_empty() else lower_name
		var photographed: Array = obj.get("photographed_subjects", [])
		if tracking_key in photographed:
			return
		photographed.append(tracking_key)
		obj["photographed_subjects"] = photographed
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track an activity photographed for photograph_activity objectives.
func track_activity_photographed(npc_id: String, npc_name: String, activity: String, quest_id: String = "") -> void:
	var lower_name := npc_name.to_lower()
	var lower_activity := activity.to_lower()

	_for_each_objective(quest_id, "photograph_activity", func(obj: Dictionary) -> void:
		if not obj.get("npc_name", "").is_empty() and obj.get("npc_name", "").to_lower() != lower_name:
			return
		if not obj.get("target_activity", "").is_empty() and not lower_activity.contains(obj.get("target_activity", "").to_lower()):
			return

		var tracking_key := "%s:%s" % [lower_name, lower_activity]
		var photographed: Array = obj.get("photographed_subjects", [])
		if tracking_key in photographed:
			return
		photographed.append(tracking_key)
		obj["photographed_subjects"] = photographed
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


## Track an activity observed for observe_activity objectives.
func track_activity_observed(npc_id: String, npc_name: String, activity: String, duration_seconds: float, quest_id: String = "") -> void:
	var lower_name := npc_name.to_lower()
	var lower_activity := activity.to_lower()

	_for_each_objective(quest_id, "observe_activity", func(obj: Dictionary) -> void:
		if not obj.get("npc_name", "").is_empty() and obj.get("npc_name", "").to_lower() != lower_name:
			return
		if not obj.get("target_activity", "").is_empty() and not lower_activity.contains(obj.get("target_activity", "").to_lower()):
			return

		var required_duration: float = obj.get("observe_duration_required", 5.0)
		if duration_seconds < required_duration:
			return

		var tracking_key := "%s:%s" % [lower_name, lower_activity]
		var observed: Array = obj.get("observed_activities", [])
		if tracking_key in observed:
			return
		observed.append(tracking_key)
		obj["observed_activities"] = observed
		obj["current_count"] = obj.get("current_count", 0) + 1
		var required: int = obj.get("required_count", 1)
		if obj["current_count"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)


# ── Physical actions ─────────────────────────────────────────────────────

## Track a physical action for perform_physical_action objectives.
## Also credits collect_item / craft_item for produced items.
func track_physical_action(action_type: String, items_produced: Array, quest_id: String = "") -> void:
	_for_each_objective(quest_id, "perform_physical_action", func(obj: Dictionary) -> void:
		if not obj.get("action_type", "").is_empty() and obj.get("action_type") != action_type:
			return
		obj["actions_completed"] = obj.get("actions_completed", 0) + 1
		var required: int = obj.get("actions_required", 1)
		if obj["actions_completed"] >= required:
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
	)

	# Physical actions that produce items also count toward collect_item and craft_item
	for item_name in items_produced:
		track_collected_item_by_name(item_name, "", quest_id)
		track_item_crafted(item_name, quest_id)


# ── Declarative trigger & event matching ─────────────────────────────────

## Complete objectives whose completion_trigger matches the given trigger string.
func track_by_trigger(trigger: String, quest_id: String = "") -> void:
	for obj in objectives:
		if obj.get("completed", false):
			continue
		if not quest_id.is_empty() and obj.get("quest_id") != quest_id:
			continue
		if obj.get("completion_trigger", "") == trigger and not _is_objective_locked(obj):
			complete_objective(obj.get("quest_id", ""), obj.get("id", ""))


## Generic event matcher using the quest-action mapping catalog.
## Returns number of objectives affected.
func handle_game_event(event_data: Dictionary) -> int:
	var event_type: String = event_data.get("type", "")
	if event_type.is_empty():
		return 0

	var affected := [0]

	for mapping in _action_mappings:
		if mapping.get("event_type", "") != event_type:
			continue

		_for_each_objective("", mapping.get("objective_type", ""), func(obj: Dictionary) -> void:
			# Check all match fields
			var match_fields: Array = mapping.get("match_fields", [])
			var all_match := true
			for rule in match_fields:
				var ev: String = str(event_data.get(rule.get("event_field", ""), ""))
				var ov: String = str(obj.get(rule.get("objective_field", ""), ""))
				if not _matches_field(rule, ev, ov):
					all_match = false
					break
			if not all_match:
				return

			# photograph_activity compound check
			if mapping.get("objective_type") == "photograph_activity":
				var obj_activity: String = obj.get("target_activity", "").to_lower()
				var ev_activity: String = str(event_data.get("subject_activity", event_data.get("activity", ""))).to_lower()
				if not obj_activity.is_empty() and (ev_activity.is_empty() or not ev_activity.contains(obj_activity)):
					return

			affected[0] += 1

			if mapping.get("has_quantity", false):
				var qty: Dictionary = mapping.get("quantity", {})
				var current_field: String = qty.get("current_field", "current_count")
				var required_field: String = qty.get("required_field", "required_count")
				var default_req: int = qty.get("default_required", 1)
				obj[current_field] = obj.get(current_field, 0) + 1
				var required: int = obj.get(required_field, default_req)
				if obj[current_field] >= required:
					complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
			else:
				complete_objective(obj.get("quest_id", ""), obj.get("id", ""))
		)

	return affected[0]


func _matches_field(rule: Dictionary, event_value: String, objective_value: String) -> bool:
	if objective_value.is_empty() and rule.get("optional", false):
		return true
	if event_value.is_empty() or objective_value.is_empty():
		return false

	var comparison: String = rule.get("comparison", "exact")
	match comparison:
		"exact":
			return event_value == objective_value
		"contains":
			return event_value.contains(objective_value) or objective_value.contains(event_value)
		"contains_lower":
			return event_value.to_lower().contains(objective_value.to_lower()) or objective_value.to_lower().contains(event_value.to_lower())
		_:
			return event_value == objective_value


# ── Position generation ──────────────────────────────────────────────────

## Register a building-check callback so spawned items avoid building interiors.
func set_point_in_building_check(check: Callable) -> void:
	_point_in_building_check = check


## Generate spread-out item positions that avoid building interiors.
func generate_item_positions(count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var radius := 30.0

	for i in range(count):
		var x := 0.0
		var z := 0.0
		for attempt in range(8):
			var angle := (PI * 2.0 * i) / count + randf_range(0.0, 0.5)
			var dist := 10.0 + randf_range(0.0, radius)
			x = cos(angle) * dist
			z = sin(angle) * dist
			if not _point_in_building_check.is_valid() or not _point_in_building_check.call(x, z):
				break
		positions.append(Vector3(x, 0.5, z))
	return positions


## Generate a single location position that avoids building interiors.
func generate_location_position() -> Vector3:
	for _attempt in range(8):
		var angle := randf_range(0.0, PI * 2.0)
		var dist := 20.0 + randf_range(0.0, 20.0)
		var x := cos(angle) * dist
		var z := sin(angle) * dist
		if not _point_in_building_check.is_valid() or not _point_in_building_check.call(x, z):
			return Vector3(x, 0.0, z)
	# Fallback — push farther out
	var fallback_angle := randf_range(0.0, PI * 2.0)
	var dist := 40.0 + randf_range(0.0, 10.0)
	return Vector3(cos(fallback_angle) * dist, 0.0, sin(fallback_angle) * dist)


## Attach debug metadata to a quest marker node (used for hover tooltips).
## Replaces floating 3D text labels with lightweight metadata.
static func set_marker_debug_label(marker: Node3D, label: String) -> void:
	if marker == null:
		return
	marker.set_meta("debug_label", label)


## Get world positions of uncollected quest items for minimap markers.
func get_collectible_item_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for obj in objectives:
		if obj.get("completed", false):
			continue
		var obj_type: String = obj.get("type", "")
		if obj_type != "collect_item" and obj_type != "identify_object" and obj_type != "find_vocabulary_items":
			continue
		var remaining: int = maxi(1, obj.get("required_count", 1) - obj.get("current_count", 0))
		positions.append_array(generate_item_positions(remaining))
	return positions


# ── Accessors ────────────────────────────────────────────────────────────

func get_active_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for q in all_quests:
		if q.get("id", "") in active_quest_ids:
			result.append(q)
	return result


func get_all_quests() -> Array[Dictionary]:
	return all_quests.duplicate()


func get_completed_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for q in all_quests:
		if q.get("id", "") in completed_quest_ids:
			result.append(q)
	return result


func get_available_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for q in all_quests:
		var qid: String = q.get("id", "")
		if qid not in active_quest_ids and qid not in completed_quest_ids:
			result.append(q)
	return result


func is_quest_active(quest_id: String) -> bool:
	return quest_id in active_quest_ids


func is_quest_completed(quest_id: String) -> bool:
	return quest_id in completed_quest_ids


func get_objectives_for_quest(quest_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obj in objectives:
		if obj.get("quest_id") == quest_id:
			result.append(obj)
	return result
