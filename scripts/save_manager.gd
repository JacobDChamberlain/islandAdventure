extends Node
# Save/load to 3 JSON slots. Saves the player's position, health, score, exotic
# matter, and which artifacts are collected. Enemies reset to spawn on load. A
# loaded slot is applied by main.gd (apply_pending) a couple frames after load.

var _pending: Dictionary = {}

func _slot_path(slot: int) -> String:
	return "user://save_%d.json" % slot

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

func slot_summary(slot: int) -> String:
	var d := _read(slot)
	if d.is_empty():
		return "— empty —"
	return "Artifacts %d/%d   HP %d" % [int(d.get("score", 0)), int(d.get("total", 8)), int(d.get("health", 0))]

func _read(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func save_to_slot(slot: int) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var pos := Vector3(0, 30, 0)
	if player:
		pos = player.global_position
	var data := {
		"pos": [pos.x, pos.y, pos.z],
		"health": Game.health,
		"score": Game.score,
		"total": Game.total_artifacts,
		"collected": Game.collected_artifacts,
		"exotic": Game.exotic_matter,
		"coins": Game.coins,
		"quest": Game.quest_active,
		"has_grapple": Game.has_grapple,
	}
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_slot(slot: int) -> void:
	var d := _read(slot)
	if d.is_empty():
		return
	_pending = d
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# Called from main.gd _ready. Waits a couple frames (so the player's own
# ground-snap runs first) then applies the loaded state.
func apply_pending() -> void:
	if _pending.is_empty():
		return
	var data := _pending
	_pending = {}
	await get_tree().process_frame
	await get_tree().process_frame
	var tree := get_tree()
	var player := tree.get_first_node_in_group("player")
	if player:
		var p = data.get("pos", [0, 30, 0])
		player.global_position = Vector3(p[0], p[1], p[2])
		if "velocity" in player:
			player.velocity = Vector3.ZERO
	Game.score = int(data.get("score", 0))
	Game.health = int(data.get("health", Game.max_health))
	Game.exotic_matter = int(data.get("exotic", 0))
	Game.coins = int(data.get("coins", 0))
	Game.quest_active = bool(data.get("quest", false))
	Game.has_grapple = bool(data.get("has_grapple", false))
	Game.collected_artifacts = data.get("collected", [])
	for artifact in tree.get_nodes_in_group("artifact"):
		if String(artifact.name) in Game.collected_artifacts:
			artifact.queue_free()
	# If the quest was already underway, reveal the remaining artifacts.
	if Game.quest_active:
		Game.quest_started.emit()
	Game.score_changed.emit(Game.score, Game.total_artifacts)
	Game.exotic_changed.emit(Game.exotic_matter)
	Game.coins_changed.emit(Game.coins)
	Game.health_changed.emit(Game.health, Game.max_health)
