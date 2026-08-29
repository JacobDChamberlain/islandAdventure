extends Area3D
# A walk-in gateway between levels. Sits on the ground (via the island/city
# height_at contract), glows, and on player entry loads `target_scene`.

@export_file("*.tscn") var target_scene: String = "res://scenes/city.tscn"
@export var label_text: String = "CITY"
@export var snap_to_ground: bool = true

var _used := false

func _ready() -> void:
	add_to_group("portal")
	if has_node("Label"):
		($Label as Label3D).text = label_text
	body_entered.connect(_on_body_entered)
	if snap_to_ground:
		await get_tree().process_frame   # let terrain collision/height come online
		var ground := get_tree().get_first_node_in_group("island")
		if ground and ground.has_method("height_at"):
			global_position.y = ground.height_at(global_position.x, global_position.z)

func _process(delta: float) -> void:
	rotate_y(delta * 1.2)   # slow spin so it reads as "active"

func _on_body_entered(body: Node) -> void:
	if _used or not body.is_in_group("player"):
		return
	if target_scene == "" or not ResourceLoader.exists(target_scene):
		push_warning("Portal: target_scene missing → " + str(target_scene))
		return
	_used = true
	Game.cinematic = false        # clear any frozen-camera state before we leave
	get_tree().paused = false
	get_tree().change_scene_to_file(target_scene)
