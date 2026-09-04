extends Area3D
# A blaster ammo crate lying around the level. Built in code (no .tscn) and
# scattered procedurally by main.gd, so both the island and the city get them
# without touching either scene. Swap `model` for a Meshy crate later — the
# greybox box mesh is only used when no model is set.

@export var ammo_amount: int = 25
@export var model: PackedScene = preload("res://assets/models/ammo_crate.glb")
@export var model_target_size: float = 0.9  # longest axis, in metres
@export var spin_speed: float = 1.2
@export var bob_height: float = 0.12
@export var bob_speed: float = 2.4
@export var rest_height: float = 0.18       # its BASE floats this far above the ground

var _base_y: float = 0.0
var _time: float = 0.0
var _visual: Node3D

func _ready() -> void:
	add_to_group("ammo")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	collision_mask = 1                       # the hero walks on layer 1
	_build_visual()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.2, 1.2)
	shape.shape = box
	add_child(shape)
	_snap_to_ground()

func _build_visual() -> void:
	if model != null:
		_visual = model.instantiate()
		add_child(_visual)
		_fit_model()
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.5, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.75, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.4
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	add_child(mi)
	_visual = mi

# Measure via GLOBAL transforms folded back into the visual's own space. Meshy
# wraps meshes in parent nodes that carry their own transform, and reading only
# `mi.transform` ignores those — which silently made the crate 1.24 m when it was
# asked for 0.90.
func _fit_model() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_visual):
		return
	var inv := _visual.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for child in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0:
		return
	var s: float = model_target_size / longest
	_visual.scale = Vector3.ONE * s
	# Stand it ON the pickup's origin rather than centred through it, so
	# rest_height means "how high its base floats" and it never sinks into a hill.
	_visual.position = -(box.position + Vector3(box.size.x * 0.5, 0.0, box.size.z * 0.5)) * s

# Same rule as every other placed thing: ask the ground how high it is, don't
# raycast (terrain collision isn't ready on the first frame).
func _snap_to_ground() -> void:
	await get_tree().process_frame
	var ground := get_tree().get_first_node_in_group("island")
	if ground and ground.has_method("height_at"):
		global_position.y = ground.height_at(global_position.x, global_position.z) + rest_height
	_base_y = global_position.y

func _process(delta: float) -> void:
	_time += delta
	rotate_y(spin_speed * delta)
	global_position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	# Driving counts: the hero is hidden inside the car, so the CAR collects.
	if body.is_in_group("player") or (body.is_in_group("vehicle") and Game.driving):
		collect()

# Public so Biscuit can fetch it for you (see cat.gd).
func collect() -> void:
	if Game.ammo >= Game.max_ammo:
		return                               # already full — leave it for later
	Fx.poof(global_position, Color(0.4, 0.9, 1.0), 10, 0.5)
	Sfx.exotic()
	Game.collect_ammo(ammo_amount)
	queue_free()
