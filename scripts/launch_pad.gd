extends Area3D
# Step on it → get flung upward. Snaps to the terrain where placed.

@export var strength: float = 40.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		global_position.y = island.height_at(global_position.x, global_position.z) + 0.25

func _on_body_entered(body: Node3D) -> void:
	if (body.is_in_group("player") or body.is_in_group("vehicle")) and body.has_method("launch"):
		body.launch(strength)
		Fx.poof(global_position, Color(0.3, 0.9, 1.0), 22, 1.4)
		Sfx.jump()
