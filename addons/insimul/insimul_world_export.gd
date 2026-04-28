class_name InsimulWorldExport
extends RefCounted
## Loads exported Insimul world data from JSON files for offline mode.
## Supports the world export format produced by:
##   curl http://localhost:8080/api/conversation/export/WORLD_ID > world_export.json


## Load world data from a file path (res:// or user:// or absolute).
static func load_from_file(path: String) -> InsimulTypes.ExportedWorld:
	if not FileAccess.file_exists(path):
		push_warning("[InsimulExport] File not found: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[InsimulExport] Failed to open: %s" % path)
		return null

	var json_text := file.get_as_text()
	file.close()
	return load_from_string(json_text)


## Load world data from a JSON string.
static func load_from_string(json_text: String) -> InsimulTypes.ExportedWorld:
	var json := JSON.parse_string(json_text)
	if json == null or not json is Dictionary:
		push_error("[InsimulExport] Invalid JSON")
		return null

	var world := InsimulTypes.ExportedWorld.new()
	world.world_name = json.get("worldName", "")
	world.world_id = json.get("worldId", "")

	# Parse characters
	var chars_arr: Array = json.get("characters", [])
	for c_data in chars_arr:
		if not c_data is Dictionary:
			continue
		var ch := InsimulTypes.ExportedCharacter.new()
		ch.character_id = c_data.get("characterId", c_data.get("id", ""))
		ch.first_name = c_data.get("firstName", "")
		ch.last_name = c_data.get("lastName", "")
		ch.gender = c_data.get("gender", "")
		ch.occupation = c_data.get("occupation", "")
		ch.birth_year = int(c_data.get("birthYear", 0))
		ch.is_alive = c_data.get("isAlive", true)

		# Personality — handle both nested and flat
		if c_data.has("personality") and c_data["personality"] is Dictionary:
			var p: Dictionary = c_data["personality"]
			ch.openness = float(p.get("openness", 0))
			ch.conscientiousness = float(p.get("conscientiousness", 0))
			ch.extroversion = float(p.get("extroversion", 0))
			ch.agreeableness = float(p.get("agreeableness", 0))
			ch.neuroticism = float(p.get("neuroticism", 0))
		else:
			ch.openness = float(c_data.get("openness", 0))
			ch.conscientiousness = float(c_data.get("conscientiousness", 0))
			ch.extroversion = float(c_data.get("extroversion", 0))
			ch.agreeableness = float(c_data.get("agreeableness", 0))
			ch.neuroticism = float(c_data.get("neuroticism", 0))

		world.characters.append(ch)

	# Parse dialogue contexts
	var ctx_arr: Array = json.get("dialogueContexts", [])
	for ctx_data in ctx_arr:
		if not ctx_data is Dictionary:
			continue
		var ctx := InsimulTypes.DialogueContext.new()
		ctx.character_id = ctx_data.get("characterId", "")
		ctx.character_name = ctx_data.get("characterName", "")
		ctx.system_prompt = ctx_data.get("systemPrompt", "")
		ctx.greeting = ctx_data.get("greeting", "")
		ctx.voice = ctx_data.get("voice", "Kore")

		var truths_arr: Array = ctx_data.get("truths", [])
		for t_data in truths_arr:
			if not t_data is Dictionary:
				continue
			var truth := InsimulTypes.DialogueTruth.new()
			truth.title = t_data.get("title", "")
			truth.content = t_data.get("content", "")
			ctx.truths.append(truth)

		world.dialogue_contexts.append(ctx)

	print("[InsimulExport] Loaded world '%s': %d characters, %d contexts" % [
		world.world_name, world.characters.size(), world.dialogue_contexts.size()])
	return world
