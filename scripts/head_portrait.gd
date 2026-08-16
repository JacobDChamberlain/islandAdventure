extends Node3D
# Drives the little 3D head shown in the HUD portrait circle. It normalizes the
# hero model to a known size, frames the camera on the head, lights it, and
# gently turns it so the portrait feels alive.

@export var yaw_offset_deg: float = 0.0    # flip to 180 if you see the back of the head
@export var oscillate_deg: float = 16.0    # how far the head turns side to side
@export var oscillate_speed: float = 0.8
@export var head_height: float = 0.86      # where the head sits on the normalized (0..1) body
@export var camera_distance: float = 0.7
@export var camera_fov: float = 30.0
@export var portrait_anim: String = "Idle_6"

@onready var model: Node3D = $Model
@onready var cam: Camera3D = $Camera3D

var _t: float = 0.0

func _ready() -> void:
	_normalize_and_frame()
	var key: DirectionalLight3D = get_node_or_null("Key")
	if key:
		key.rotation_degrees = Vector3(-20, 25, 0)
	var fill: DirectionalLight3D = get_node_or_null("Fill")
	if fill:
		fill.rotation_degrees = Vector3(-5, -150, 0)
	# Play a calm looping idle in the portrait (override any autoplay clip).
	var ap: AnimationPlayer = model.get_node_or_null("AnimationPlayer")
	if ap:
		if ap.has_animation(portrait_anim):
			ap.get_animation(portrait_anim).loop_mode = Animation.LOOP_LINEAR
			ap.play(portrait_anim)
		else:
			ap.stop()

func _process(delta: float) -> void:
	_t += delta
	if model:
		model.rotation_degrees.y = yaw_offset_deg + sin(_t * oscillate_speed) * oscillate_deg

func _normalize_and_frame() -> void:
	if model == null:
		return
	var aabb := _model_aabb()
	if aabb.size.y <= 0.0:
		return
	# Scale so the body is 1.0 unit tall, feet at y = 0, roughly centered on X/Z.
	var s := 1.0 / aabb.size.y
	model.scale = Vector3.ONE * s
	model.position = Vector3(
		-(aabb.position.x + aabb.size.x * 0.5) * s,
		-aabb.position.y * s,
		-(aabb.position.z + aabb.size.z * 0.5) * s
	)
	model.rotation_degrees.y = yaw_offset_deg
	# Frame the camera on the head.
	cam.position = Vector3(0.0, head_height, camera_distance)
	cam.look_at(Vector3(0.0, head_height, 0.0), Vector3.UP)
	cam.fov = camera_fov
	cam.make_current()

func _model_aabb() -> AABB:
	# Measure the skeleton's true extent for rigged models (the bind-pose mesh AABB
	# ignores the ~100x scale Meshy bakes into the rig). Fall back to mesh AABB.
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		var skel := skels[0] as Skeleton3D
		var inv := model.global_transform.affine_inverse()
		var aabb := AABB()
		var first := true
		for i in skel.get_bone_count():
			var p: Vector3 = inv * (skel.global_transform * skel.get_bone_global_pose(i)).origin
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
		if not first:
			return aabb
	var result := AABB()
	var first_mesh := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_model := model.global_transform.affine_inverse() * mi.global_transform
		var box := to_model * mi.mesh.get_aabb()
		if first_mesh:
			result = box
			first_mesh = false
		else:
			result = result.merge(box)
	return result
