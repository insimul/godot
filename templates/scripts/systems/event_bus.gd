extends Node
## EventBus — autoloaded singleton.
## Centralized typed event system that bridges player actions to quest tracking
## and Prolog fact assertion. All game actions (combat, items, dialogue, etc.)
## emit events through this bus, which subscribers consume to update state.
##
## Mirrors GameEventBus.ts from the Babylon.js source.

## All event type constants.
const EVENT_ITEM_COLLECTED := "item_collected"
const EVENT_ENEMY_DEFEATED := "enemy_defeated"
const EVENT_LOCATION_VISITED := "location_visited"
const EVENT_NPC_TALKED := "npc_talked"
const EVENT_ITEM_DELIVERED := "item_delivered"
const EVENT_VOCABULARY_USED := "vocabulary_used"
const EVENT_CONVERSATION_TURN := "conversation_turn"
const EVENT_QUEST_ACCEPTED := "quest_accepted"
const EVENT_QUEST_COMPLETED := "quest_completed"
const EVENT_QUEST_OBJECTIVE_COMPLETED := "quest_objective_completed"
const EVENT_COMBAT_ACTION := "combat_action"
const EVENT_REPUTATION_CHANGED := "reputation_changed"
const EVENT_ITEM_PURCHASED := "item_purchased"
const EVENT_GIFT_GIVEN := "gift_given"
const EVENT_ITEM_CRAFTED := "item_crafted"
const EVENT_LOCATION_DISCOVERED := "location_discovered"
const EVENT_SETTLEMENT_ENTERED := "settlement_entered"
const EVENT_PUZZLE_SOLVED := "puzzle_solved"
const EVENT_ITEM_REMOVED := "item_removed"
const EVENT_ITEM_USED := "item_used"
const EVENT_ITEM_DROPPED := "item_dropped"
const EVENT_ITEM_EQUIPPED := "item_equipped"
const EVENT_ITEM_UNEQUIPPED := "item_unequipped"
const EVENT_UTTERANCE_EVALUATED := "utterance_evaluated"
const EVENT_UTTERANCE_QUEST_PROGRESS := "utterance_quest_progress"
const EVENT_UTTERANCE_QUEST_COMPLETED := "utterance_quest_completed"
const EVENT_AMBIENT_CONVERSATION_STARTED := "ambient_conversation_started"
const EVENT_AMBIENT_CONVERSATION_ENDED := "ambient_conversation_ended"
const EVENT_VOCABULARY_OVERHEARD := "vocabulary_overheard"
const EVENT_STATE_CREATED_TRUTH := "state_created_truth"
const EVENT_STATE_EXPIRED_TRUTH := "state_expired_truth"
const EVENT_ROMANCE_ACTION := "romance_action"
const EVENT_ROMANCE_STAGE_CHANGED := "romance_stage_changed"
const EVENT_NPC_VOLITION_ACTION := "npc_volition_action"
const EVENT_PUZZLE_FAILED := "puzzle_failed"
const EVENT_QUEST_FAILED := "quest_failed"
const EVENT_QUEST_ABANDONED := "quest_abandoned"
const EVENT_QUEST_DECLINED := "quest_declined"
const EVENT_CONVERSATION_OVERHEARD := "conversation_overheard"
const EVENT_CREATE_TRUTH := "create_truth"
# Assessment / onboarding events
const EVENT_ASSESSMENT_STARTED := "assessment_started"
const EVENT_ASSESSMENT_PHASE_STARTED := "assessment_phase_started"
const EVENT_ASSESSMENT_PHASE_COMPLETED := "assessment_phase_completed"
const EVENT_ASSESSMENT_TIER_CHANGE := "assessment_tier_change"
const EVENT_ASSESSMENT_COMPLETED := "assessment_completed"
const EVENT_ONBOARDING_STEP_STARTED := "onboarding_step_started"
const EVENT_ONBOARDING_STEP_COMPLETED := "onboarding_step_completed"
const EVENT_ONBOARDING_COMPLETED := "onboarding_completed"
const EVENT_PERIODIC_ASSESSMENT_TRIGGERED := "periodic_assessment_triggered"
const EVENT_ASSESSMENT_CONVERSATION_QUEST_START := "assessment_conversation_quest_start"
const EVENT_ASSESSMENT_CONVERSATION_COMPLETED := "assessment_conversation_completed"
# Visual vocabulary quest events
const EVENT_VISUAL_VOCAB_PROMPTED := "visual_vocab_prompted"
const EVENT_VISUAL_VOCAB_ANSWERED := "visual_vocab_answered"
# Follow directions quest events
const EVENT_DIRECTION_STEP_COMPLETED := "direction_step_completed"
# Pronunciation quest events
const EVENT_PRONUNCIATION_ASSESSMENT_DATA := "pronunciation_assessment_data"
# Point-and-name vocabulary events
const EVENT_OBJECT_NAMED := "object_named"
# Object examination events
const EVENT_OBJECT_EXAMINED := "object_examined"
# NPC exam events
const EVENT_NPC_EXAM_STARTED := "npc_exam_started"
const EVENT_NPC_EXAM_LISTENING_READY := "npc_exam_listening_ready"
const EVENT_NPC_EXAM_QUESTION_ANSWERED := "npc_exam_question_answered"
# Achievement events
const EVENT_ACHIEVEMENT_UNLOCKED := "achievement_unlocked"
# Quest notification & reminder events
const EVENT_QUEST_REMINDER := "quest_reminder"
const EVENT_QUEST_EXPIRED := "quest_expired"
const EVENT_QUEST_MILESTONE := "quest_milestone"
const EVENT_DAILY_QUESTS_RESET := "daily_quests_reset"
# NPC exam events
const EVENT_NPC_EXAM_REQUESTED := "npc_exam_requested"
const EVENT_NPC_EXAM_COMPLETED := "npc_exam_completed"
# Topic-tagged conversation turn events
const EVENT_NPC_CONVERSATION_TURN := "npc_conversation_turn"
# Skill reward events
const EVENT_SKILL_REWARDS_APPLIED := "skill_rewards_applied"
# Assessment conversation events
const EVENT_ASSESSMENT_CONVERSATION_INITIATED := "assessment_conversation_initiated"
const EVENT_ASSESSMENT_GUIDED_CONVERSATION_START := "assessment_guided_conversation_start"
# Generic feature-module events (knowledge, identification)
const EVENT_KNOWLEDGE_APPLIED := "knowledge_applied"
const EVENT_IDENTIFICATION_PROMPTED := "identification_prompted"
const EVENT_IDENTIFICATION_CORRECT := "identification_correct"
const EVENT_IDENTIFICATION_INCORRECT := "identification_incorrect"
# Playthrough completion events
const EVENT_PLAYTHROUGH_COMPLETED := "playthrough_completed"
const EVENT_PLAYTHROUGH_COMPLETION_REQUESTED := "playthrough_completion_requested"
const EVENT_DEPARTURE_ASSESSMENT_TRIGGERED := "departure_assessment_triggered"
# Time events
const EVENT_HOUR_CHANGED := "hour_changed"
const EVENT_DAY_CHANGED := "day_changed"
const EVENT_TIME_OF_DAY_CHANGED := "time_of_day_changed"
# Object identification events
const EVENT_OBJECT_IDENTIFIED := "object_identified"
# Sign reading events
const EVENT_SIGN_READ := "sign_read"
# NPC relationship events
const EVENT_NPC_RELATIONSHIP_CHANGED := "npc_relationship_changed"
# Container events
const EVENT_CONTAINER_OPENED := "container_opened"
# Escort quest events
const EVENT_ESCORT_STARTED := "escort_started"
const EVENT_ESCORT_COMPLETED := "escort_completed"
# Mercantile events
const EVENT_FOOD_ORDERED := "food_ordered"
const EVENT_PRICE_HAGGLED := "price_haggled"
# Text collection events
const EVENT_TEXT_COLLECTED := "text_collected"
# XP and level-up events
const EVENT_XP_GAINED := "xp_gained"
const EVENT_LEVEL_UP := "level_up"
# Vocabulary hover-lookup events
const EVENT_VOCABULARY_LOOKUP := "vocabulary_lookup"
# Vehicle events
const EVENT_VEHICLE_MOUNTED := "vehicle_mounted"
const EVENT_VEHICLE_DISMOUNTED := "vehicle_dismounted"
# Photography events
const EVENT_PHOTO_TAKEN := "photo_taken"
# Furniture interaction events
const EVENT_FURNITURE_SAT := "furniture_sat"
const EVENT_FURNITURE_STOOD := "furniture_stood"
const EVENT_FURNITURE_SLEPT := "furniture_slept"
const EVENT_FURNITURE_READ_LORE := "furniture_read_lore"
const EVENT_FURNITURE_WORKED := "furniture_worked"
# Clue discovery events
const EVENT_CLUE_DISCOVERED := "clue_discovered"
# Conversational action events
const EVENT_CONVERSATIONAL_ACTION := "conversational_action"
const EVENT_CONVERSATION_TURN_COUNTED := "conversation_turn_counted"
# Physical action events
const EVENT_PHYSICAL_ACTION_COMPLETED := "physical_action_completed"
# Reading completion events
const EVENT_READING_COMPLETED := "reading_completed"
const EVENT_QUESTIONS_ANSWERED := "questions_answered"
# Assessment objective triggers
const EVENT_WRITING_SUBMITTED := "writing_submitted"
const EVENT_LISTENING_COMPLETED := "listening_completed"
# Exploration discovery events
const EVENT_INVESTIGATION_COMPLETED := "investigation_completed"
# NPC activity observation events
const EVENT_ACTIVITY_OBSERVED := "activity_observed"
# UI panel events (tutorial completion triggers)
const EVENT_INVENTORY_OPENED := "inventory_opened"
const EVENT_QUEST_LOG_OPENED := "quest_log_opened"
# CEFR level advancement (auto-level-up after conversation)
const EVENT_CEFR_LEVEL_ADVANCED := "cefr_level_advanced"
# Volition schedule events
const EVENT_VOLITION_SCHEDULE_OVERRIDE := "volition_schedule_override"
const EVENT_VOLITION_RETURN_TO_SCHEDULE := "volition_return_to_schedule"
# NPC greeting events
const EVENT_NPC_GREETING := "npc_greeting"
# Item sold events
const EVENT_ITEM_SOLD := "item_sold"
# Conversation assessment completed
const EVENT_CONVERSATION_ASSESSMENT_COMPLETED := "conversation_assessment_completed"
# Unified action execution event
const EVENT_ACTION_EXECUTED := "action_executed"
# NPC speech act events
const EVENT_NPC_SPEECH_ACT := "npc_speech_act"
# Grammar weakness events
const EVENT_GRAMMAR_WEAKNESS_DETECTED := "grammar_weakness_detected"
# Player proximity events
const EVENT_PLAYER_NEAR_NPC := "player_near_npc"
# Conversational action completed
const EVENT_CONVERSATIONAL_ACTION_COMPLETED := "conversational_action_completed"
# Text events
const EVENT_TEXT_FOUND := "text_found"
const EVENT_TEXT_READ := "text_read"
# Object point-and-name events
const EVENT_OBJECT_POINTED_AND_NAMED := "object_pointed_and_named"
# Translation / pronunciation attempt events
const EVENT_TRANSLATION_ATTEMPT := "translation_attempt"
const EVENT_PRONUNCIATION_ATTEMPT := "pronunciation_attempt"

## Valid event types for validation.
const VALID_EVENT_TYPES: Array[String] = [
	EVENT_ITEM_COLLECTED, EVENT_ENEMY_DEFEATED, EVENT_LOCATION_VISITED,
	EVENT_NPC_TALKED, EVENT_ITEM_DELIVERED, EVENT_VOCABULARY_USED,
	EVENT_CONVERSATION_TURN, EVENT_QUEST_ACCEPTED, EVENT_QUEST_COMPLETED,
	EVENT_QUEST_OBJECTIVE_COMPLETED, EVENT_COMBAT_ACTION, EVENT_REPUTATION_CHANGED, EVENT_ITEM_PURCHASED,
	EVENT_GIFT_GIVEN, EVENT_ITEM_CRAFTED,
	EVENT_LOCATION_DISCOVERED, EVENT_SETTLEMENT_ENTERED, EVENT_PUZZLE_SOLVED,
	EVENT_ITEM_REMOVED, EVENT_ITEM_USED, EVENT_ITEM_DROPPED,
	EVENT_ITEM_EQUIPPED, EVENT_ITEM_UNEQUIPPED,
	EVENT_UTTERANCE_EVALUATED, EVENT_UTTERANCE_QUEST_PROGRESS,
	EVENT_UTTERANCE_QUEST_COMPLETED, EVENT_AMBIENT_CONVERSATION_STARTED,
	EVENT_AMBIENT_CONVERSATION_ENDED, EVENT_VOCABULARY_OVERHEARD,
	EVENT_STATE_CREATED_TRUTH, EVENT_STATE_EXPIRED_TRUTH,
	EVENT_ROMANCE_ACTION, EVENT_ROMANCE_STAGE_CHANGED,
	EVENT_NPC_VOLITION_ACTION, EVENT_PUZZLE_FAILED,
	EVENT_QUEST_FAILED, EVENT_QUEST_ABANDONED, EVENT_QUEST_DECLINED,
	EVENT_CONVERSATION_OVERHEARD, EVENT_CREATE_TRUTH,
	EVENT_ASSESSMENT_STARTED, EVENT_ASSESSMENT_PHASE_STARTED,
	EVENT_ASSESSMENT_PHASE_COMPLETED, EVENT_ASSESSMENT_TIER_CHANGE,
	EVENT_ASSESSMENT_COMPLETED, EVENT_ONBOARDING_STEP_STARTED,
	EVENT_ONBOARDING_STEP_COMPLETED, EVENT_ONBOARDING_COMPLETED,
	EVENT_PERIODIC_ASSESSMENT_TRIGGERED,
	EVENT_ASSESSMENT_CONVERSATION_QUEST_START,
	EVENT_ASSESSMENT_CONVERSATION_COMPLETED,
	EVENT_VISUAL_VOCAB_PROMPTED,
	EVENT_VISUAL_VOCAB_ANSWERED,
	EVENT_DIRECTION_STEP_COMPLETED,
	EVENT_PRONUNCIATION_ASSESSMENT_DATA,
	EVENT_OBJECT_NAMED,
	EVENT_OBJECT_EXAMINED,
	EVENT_NPC_EXAM_STARTED,
	EVENT_NPC_EXAM_LISTENING_READY,
	EVENT_NPC_EXAM_QUESTION_ANSWERED,
	EVENT_ACHIEVEMENT_UNLOCKED,
	EVENT_QUEST_REMINDER,
	EVENT_QUEST_EXPIRED,
	EVENT_QUEST_MILESTONE,
	EVENT_DAILY_QUESTS_RESET,
	EVENT_NPC_EXAM_REQUESTED,
	EVENT_NPC_EXAM_COMPLETED,
	EVENT_NPC_CONVERSATION_TURN,
	EVENT_SKILL_REWARDS_APPLIED,
	EVENT_ASSESSMENT_CONVERSATION_INITIATED,
	EVENT_ASSESSMENT_GUIDED_CONVERSATION_START,
	EVENT_KNOWLEDGE_APPLIED,
	EVENT_IDENTIFICATION_PROMPTED,
	EVENT_IDENTIFICATION_CORRECT,
	EVENT_IDENTIFICATION_INCORRECT,
	EVENT_OBJECT_IDENTIFIED,
	EVENT_SIGN_READ,
	EVENT_PLAYTHROUGH_COMPLETED,
	EVENT_PLAYTHROUGH_COMPLETION_REQUESTED,
	EVENT_DEPARTURE_ASSESSMENT_TRIGGERED,
	# Time events
	EVENT_HOUR_CHANGED,
	EVENT_DAY_CHANGED,
	EVENT_TIME_OF_DAY_CHANGED,
	# NPC relationship events
	EVENT_NPC_RELATIONSHIP_CHANGED,
	# Container events
	EVENT_CONTAINER_OPENED,
	# Escort quest events
	EVENT_ESCORT_STARTED,
	EVENT_ESCORT_COMPLETED,
	# Mercantile events
	EVENT_ITEM_PURCHASED,
	EVENT_FOOD_ORDERED,
	EVENT_PRICE_HAGGLED,
	# Text collection events
	EVENT_TEXT_COLLECTED,
	EVENT_VOCABULARY_LOOKUP,
	# Vehicle events
	EVENT_VEHICLE_MOUNTED,
	EVENT_VEHICLE_DISMOUNTED,
	# Photography events
	EVENT_PHOTO_TAKEN,
	# Furniture interaction events
	EVENT_FURNITURE_SAT,
	EVENT_FURNITURE_STOOD,
	EVENT_FURNITURE_SLEPT,
	EVENT_FURNITURE_READ_LORE,
	EVENT_FURNITURE_WORKED,
	# Clue discovery events
	EVENT_CLUE_DISCOVERED,
	# Conversational action events
	EVENT_CONVERSATIONAL_ACTION,
	EVENT_CONVERSATION_TURN_COUNTED,
	# Physical action events
	EVENT_PHYSICAL_ACTION_COMPLETED,
	# Reading completion events
	EVENT_READING_COMPLETED,
	EVENT_QUESTIONS_ANSWERED,
	# Assessment objective triggers
	EVENT_WRITING_SUBMITTED,
	EVENT_LISTENING_COMPLETED,
	# Exploration discovery events
	EVENT_INVESTIGATION_COMPLETED,
	# NPC activity observation events
	EVENT_ACTIVITY_OBSERVED,
	# UI panel events (tutorial completion triggers)
	EVENT_INVENTORY_OPENED,
	EVENT_QUEST_LOG_OPENED,
	# CEFR level advancement
	EVENT_CEFR_LEVEL_ADVANCED,
	# Volition schedule events
	EVENT_VOLITION_SCHEDULE_OVERRIDE,
	EVENT_VOLITION_RETURN_TO_SCHEDULE,
	# NPC greeting events
	EVENT_NPC_GREETING,
	# Item sold events
	EVENT_ITEM_SOLD,
	# Conversation assessment completed
	EVENT_CONVERSATION_ASSESSMENT_COMPLETED,
	# Unified action execution event
	EVENT_ACTION_EXECUTED,
	# NPC speech act events
	EVENT_NPC_SPEECH_ACT,
	# Grammar weakness events
	EVENT_GRAMMAR_WEAKNESS_DETECTED,
	# Player proximity events
	EVENT_PLAYER_NEAR_NPC,
	# Conversational action completed
	EVENT_CONVERSATIONAL_ACTION_COMPLETED,
	# Text events
	EVENT_TEXT_FOUND,
	EVENT_TEXT_READ,
	# Object point-and-name events
	EVENT_OBJECT_POINTED_AND_NAMED,
	# Translation / pronunciation attempt events
	EVENT_TRANSLATION_ATTEMPT,
	EVENT_PRONUNCIATION_ATTEMPT,
]

## Handlers keyed by event type. Each value is an Array of Callables.
var _handlers: Dictionary = {}

## Global handlers that receive all events.
var _global_handlers: Array[Callable] = []


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Emit an event to all registered handlers.
## [param event] Dictionary with at least a "type" key.
## Expected payload shapes per type:
##   item_collected:      {type, item_id, item_name, quantity, source?, taxonomy?}
##   enemy_defeated:      {type, entity_id, enemy_type}
##   location_visited:    {type, location_id, location_name}
##   npc_talked:          {type, npc_id, npc_name, turn_count}
##   item_delivered:      {type, npc_id, item_id, item_name}
##   vocabulary_used:     {type, word, correct, category?}
##   conversation_turn:   {type, npc_id, keywords}
##   quest_accepted:      {type, quest_id, quest_title, assigned_by_npc_id?, assigned_by_npc_name?}
##   quest_completed:     {type, quest_id, assigned_by_npc_id?}
##   quest_objective_completed: {type, quest_id, objective_id}
##   combat_action:       {type, action_type, target_id}
##   reputation_changed:  {type, faction_id, delta}
##   item_crafted:        {type, item_id, item_name, quantity, taxonomy?}
##   location_discovered: {type, location_id, location_name}
##   settlement_entered:  {type, settlement_id, settlement_name}
##   puzzle_solved:       {type, puzzle_id}
##   item_removed:        {type, item_id, item_name, quantity}
##   item_used:           {type, item_id, item_name}
##   item_dropped:        {type, item_id, item_name, quantity}
##   item_equipped:       {type, item_id, item_name, slot}
##   item_unequipped:     {type, item_id, item_name, slot}
##   utterance_evaluated: {type, objective_id, input, score, passed, feedback}
##   utterance_quest_progress: {type, quest_id, objective_id, current, required, percentage}
##   utterance_quest_completed: {type, quest_id, objective_id, final_score, xp_awarded, pronunciation_bonus_xp?}
##   ambient_conversation_started: {type, conversation_id, participants, location_id, topic}
##   ambient_conversation_ended: {type, conversation_id, participants, duration_ms, vocabulary_count}
##   vocabulary_overheard: {type, word, translation, language, context, conversation_id, speaker_npc_id}
##   state_created_truth: {type, character_id, state_type, cause, title, content, entry_type}
##   state_expired_truth: {type, character_id, state_type, cause, title, content, entry_type}
##   romance_action:      {type, npc_id, npc_name, action_type, accepted, stage_change?}
##   romance_stage_changed: {type, npc_id, npc_name, from_stage, to_stage}
##   npc_volition_action: {type, npc_id, action_id, target_id, score}
##   puzzle_failed:       {type, puzzle_id, puzzle_type, attempts}
##   quest_failed:        {type, quest_id, assigned_by_npc_id?}
##   quest_abandoned:     {type, quest_id, assigned_by_npc_id?}
##   quest_declined:      {type, npc_id, npc_name, quest_title?}
##   conversation_overheard: {type, npc_id_1, npc_id_2, topic, language_used}
##   create_truth:        {type, character_id, title, content, entry_type, category?}
##   assessment_started:  {type, session_id, instrument_id, phase, participant_id, assessment_type?, player_id?}
##   assessment_phase_started: {type, session_id, instrument_id, phase, phase_id?, phase_index?}
##   assessment_phase_completed: {type, session_id, instrument_id, phase, score, subscale_scores?, phase_id?, max_score?}
##   assessment_tier_change: {type, participant_id, instrument_id, from_tier, to_tier, score}
##   assessment_completed: {type, session_id, instrument_id, total_score, gain_score?, total_max_score?, cefr_level?}
##   onboarding_step_started: {type, step_id, step_index, total_steps}
##   onboarding_step_completed: {type, step_id, step_index, total_steps, duration_ms}
##   onboarding_completed: {type, total_steps, total_duration_ms}
##   periodic_assessment_triggered: {type, level, tier}
##   assessment_conversation_quest_start: {type, phase_id, topics, min_exchanges, max_exchanges}
##   assessment_conversation_completed: {type, npc_id, score?, transcript?}
##     transcript: Array[Dictionary] — each entry {role: "user"|"assistant"|"system", content: String}.
##     Populated by the chat panel; consumed by the server grader for per-turn rubric scoring.
##   visual_vocab_prompted: {type, target_id, quest_id, objective_id, is_activity}
##   visual_vocab_answered: {type, target_id, quest_id, passed, score, player_answer}
##   direction_step_completed: {type, quest_id, objective_id, step_index, steps_completed, steps_required}
##   pronunciation_assessment_data: {type, quest_id, average_score, sample_count}
##   object_named:        {type, object_id, target_word, category, correct, attempts}
##   object_examined:     {type, object_id, object_name, target_word, target_language, pronunciation?, category?}
##   npc_exam_started:     {type, exam_id, npc_id, npc_name, business_type?, exam_type?, category?, question_count?}
##   npc_exam_listening_ready: {type, exam_id, audio_url?, passage, questions, max_replays}
##   npc_exam_question_answered: {type, exam_id, question_id, correct, score, max_points}
##   achievement_unlocked: {type, achievement_id, achievement_name, description, icon}
##   quest_reminder:      {type, quest_id, quest_title, message, reminder_type}
##   quest_expired:       {type, quest_id, quest_title}
##   quest_milestone:     {type, milestone_type, label}
##   daily_quests_reset:  {type}
##   npc_exam_requested:  {type, npc_id, npc_name, exam_type, business_context?}
##   npc_exam_completed:  {type, npc_id?, exam_type, total_score, max_score, cefr_level}
##   npc_conversation_turn: {type, npc_id, topic_tag}
##   skill_rewards_applied: {type, quest_id, rewards}
##   assessment_conversation_initiated: {type, npc_id}
##   assessment_guided_conversation_start: {type, topics, min_exchanges, max_exchanges}
##   knowledge_applied:   {type, key, correct}
##   identification_prompted: {type, target_id, quest_id, objective_id, is_activity}
##   identification_correct: {type, target_id, quest_id, score, player_answer}
##   identification_incorrect: {type, target_id, quest_id, score, player_answer}
##   playthrough_completed: {type, playthrough_id, playtime, quests_completed, npcs_interacted, vocabulary_learned, cefr_start, cefr_end}
##   playthrough_completion_requested: {type, trigger}
##   departure_assessment_triggered: {type, playthrough_id}
##   hour_changed:        {type, hour, day}
##   day_changed:         {type, day, timestep}
##   time_of_day_changed: {type, from, to, hour}
##   volition_schedule_override: {type, npc_id, goal_id, reason, return_to_schedule}
##   volition_return_to_schedule: {type, npc_id, goal_id}
##   npc_greeting: {type, npc_id, npc_name, language, greeting_text, is_first_meeting}
##   item_sold: {type, item_id, item_name, quantity, total_price, merchant_id?, merchant_name?}
##   conversation_assessment_completed: {type, npc_id, turn_count, quest_id?}
##   action_executed: {type, action_name, actor_id, actor_name?, target_id?, target_name?, category?, result?, item_name?, item_type?, xp_gained?, energy_cost?}
##   npc_speech_act: {type, npc_id, npc_name, action_type, extracted_data?}
##   grammar_weakness_detected: {type, pattern, error_rate, total_attempts}
##   player_near_npc: {type, npc_id, npc_name, world_id, distance}
##   conversational_action_completed: {type, action, npc_id, quest_id?}
##   text_found: {type, text_id, text_name?}
##   text_read: {type, text_id, title?}
##   object_pointed_and_named: {type, object_id, object_name, target_word?, category?, quest_id?}
##   translation_attempt: {type, phrase, is_correct, quest_id?}
##   pronunciation_attempt: {type, phrase, score, passed, quest_id?}
##
## source (optional String): "container", "shop", "world", "gift", "craft", "quest_reward"
## taxonomy (optional Dictionary): {category, material, base_type, rarity, item_type}
func emit_event(event: Dictionary) -> void:
	var event_type: String = event.get("type", "")
	if event_type.is_empty():
		push_error("[EventBus] Cannot emit event without a 'type' key.")
		return

	# Type-specific handlers
	if _handlers.has(event_type):
		var handlers: Array = _handlers[event_type]
		for handler: Callable in handlers:
			_safe_call(handler, event, event_type)

	# Global handlers
	for handler: Callable in _global_handlers:
		_safe_call(handler, event, "global")


## Subscribe to a specific event type. Returns the callable for later disconnect.
func connect_event(event_type: String, handler: Callable) -> Callable:
	if not _handlers.has(event_type):
		_handlers[event_type] = [] as Array[Callable]
	var handler_list: Array = _handlers[event_type]
	if handler not in handler_list:
		handler_list.append(handler)
	return handler


## Subscribe to all events. Returns the callable for later disconnect.
func connect_any(handler: Callable) -> Callable:
	if handler not in _global_handlers:
		_global_handlers.append(handler)
	return handler


## Disconnect a handler from a specific event type.
func disconnect_event(event_type: String, handler: Callable) -> void:
	if _handlers.has(event_type):
		var handler_list: Array = _handlers[event_type]
		handler_list.erase(handler)


## Disconnect a global handler.
func disconnect_any(handler: Callable) -> void:
	_global_handlers.erase(handler)


## Remove all handlers and reset state.
func dispose() -> void:
	_handlers.clear()
	_global_handlers.clear()
	print("[Insimul] EventBus disposed")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Safely invoke a handler, catching errors.
func _safe_call(handler: Callable, event: Dictionary, context: String) -> void:
	if not handler.is_valid():
		push_error("[EventBus] Invalid handler in context '%s', skipping." % context)
		return
	handler.call(event)
