extends Node
## Crafting System

var recipes: Array[Dictionary] = []

func can_craft(recipe_id: String) -> bool:
	for recipe in recipes:
		if recipe.get("id", "") == recipe_id:
			var inputs: Array = recipe.get("inputItemIds", [])
			var counts: Array = recipe.get("inputCounts", [])
			for i in range(inputs.size()):
				if InventorySystem.get_item_count(inputs[i]) < counts[i]:
					return false
			return true
	return false

func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	for recipe in recipes:
		if recipe.get("id", "") == recipe_id:
			var inputs: Array = recipe.get("inputItemIds", [])
			var counts: Array = recipe.get("inputCounts", [])
			for i in range(inputs.size()):
				InventorySystem.remove_item(inputs[i], counts[i])
			InventorySystem.add_item(recipe.get("outputItemId", ""), recipe.get("outputCount", 1))
			print("[Insimul] Crafted: %s" % recipe.get("name", recipe_id))
			return true
	return false
