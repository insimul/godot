extends Node3D
## Procedural dungeon generator.

func generate_dungeon(seed_str: String, floor_count: int, rooms_per_floor: int) -> void:
	# TODO: Generate dungeon rooms and corridors procedurally
	print("[Insimul] ProceduralDungeonGenerator — %d floors, %d rooms (seed: %s)" % [floor_count, rooms_per_floor, seed_str])
