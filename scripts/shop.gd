extends Node3D
# The shop shack (just the building now — the CAT is the shopkeeper you talk to;
# see cat.gd). Snaps to the ground and swaps in an optional Meshy shack model.

# Optional Meshy shack model (replaces the greybox shack).
@export var shop_model: PackedScene = null
@export var model_scale: float = 0.0            # 0 = auto-fit to model_target_size
@export var model_target_size: float = 5.0      # auto-fit the longest horizontal axis to this
@export var model_y_offset: float = 0.0
@export var model_rotation_deg: Vector3 = Vector3.ZERO   # orient the shack (open front toward -Z)

func _ready() -> void:
	add_to_group("shop")
	await get_tree().process_frame
	_snap_to_ground()
	_setup_model()

func _snap_to_ground() -> void:
	var g := get_tree().get_first_node_in_group("island")
	if g and g.has_method("height_at"):
		global_position.y = g.height_at(global_position.x, global_position.z)

# Swap in the Meshy shack: instance it, orient, auto-fit to the ground, hide greybox.
func _setup_model() -> void:
	if shop_model == null:
		return
	var model := shop_model.instantiate() as Node3D
	if model == null:
		return
	var holder := Node3D.new()
	holder.name = "Model"
	add_child(holder)
	holder.add_child(model)
	model.rotation_degrees = model_rotation_deg
	var aabb := _model_aabb(holder)
	if aabb.size.length() > 0.001:
		var longest: float = maxf(aabb.size.x, aabb.size.z)
		var s: float = model_scale if model_scale > 0.0 else model_target_size / maxf(longest, 0.001)
		model.scale = Vector3.ONE * s
		var c := aabb.get_center()
		# Centre on X/Z; sit the base on the ground (+ manual nudge).
		model.position = Vector3(-c.x * s, -aabb.position.y * s + model_y_offset, -c.z * s)
	var greybox := get_node_or_null("Greybox") as Node3D
	if greybox:
		greybox.visible = false

func _model_aabb(frame: Node3D) -> AABB:
	var inv := frame.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for c in frame.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			out = box; first = false
		else:
			out = out.merge(box)
	return out
