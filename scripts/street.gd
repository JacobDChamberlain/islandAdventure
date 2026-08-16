extends Node3D
# Places the Meshy "street" model as a scaled, walkable landmark: scales it up,
# builds trimesh collision, and sits it as a raised plaza on the terrain.

@export var street_scale: float = 18.0
@export var y_offset: float = 0.0   # manual nudge on top of the auto ground-placement

@onready var model: Node3D = $Model

func _ready() -> void:
	model.scale = Vector3.ONE * street_scale
	var bottom := 0.0
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() > 0:
		var mi := meshes[0] as MeshInstance3D
		bottom = mi.get_aabb().position.y   # local (unscaled) min y
		mi.create_trimesh_collision()       # solid + walkable

	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		# Highest terrain under the footprint → sits on top as a raised plaza.
		var max_h := -1000.0
		for gx in range(-3, 4):
			for gz in range(-3, 4):
				var px := global_position.x + gx * street_scale / 3.0
				var pz := global_position.z + gz * street_scale / 3.0
				max_h = maxf(max_h, island.height_at(px, pz))
		global_position.y = max_h - bottom * street_scale + y_offset
