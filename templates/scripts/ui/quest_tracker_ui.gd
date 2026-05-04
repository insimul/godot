extends Control
## Quest tracker panel — shows active quests.

@onready var quest_list: RichTextLabel = $QuestList if has_node("QuestList") else null

func _process(_delta: float) -> void:
	if quest_list == null:
		return
	var active: Array = QuestSystem.get_active_quests()
	if active.is_empty():
		quest_list.text = "No active quests"
		return
	var text := ""
	for q in active:
		text += "[b]%s[/b]\n  %s\n" % [q.get("title", "?"), q.get("description", "")]
	quest_list.text = text
