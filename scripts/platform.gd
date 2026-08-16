extends StaticBody3D
# A static platform to climb on; snaps to the terrain at its x/z plus an offset.

@export var base_offset: float = 2.0

func _ready() -> void:
	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		global_position.y = island.height_at(global_position.x, global_position.z) + base_offset
