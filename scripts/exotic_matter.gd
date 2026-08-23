extends Area3D
# A rare "Exotic Matter" pickup. Heads drop these (sometimes) when defeated. On
# spawn it POPS OUT in an arc and can't be picked up for a moment, so you always
# see it land instead of vacuuming it up the instant it appears under a stomped
# enemy. Once it settles it spins and bobs like an artifact, glows violet, and
# feeds Game.exotic_matter (never gates the win).

@export var spin_speed: float = 3.2
@export var bob_height: float = 0.3
@export var bob_speed: float = 3.0
@export var model_size: float = 0.9        # fit the Meshy model to this size (meters)
@export var pop_up_speed: float = 7.0      # initial upward pop
@export var pop_side_speed: float = 2.0    # random horizontal scatter
@export var drop_gravity: float = 22.0
@export var rest_height: float = 1.2       # how high it floats above ground once settled
@export var arm_delay: float = 0.5         # can't be collected for this long after spawning

var _base_y: float = 0.0
var _time: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _grounded: bool = false
var _armed: bool = false
var _island: Node = null

func _ready() -> void:
	add_to_group("exotic")
	_fit_model($Model, model_size)
	body_entered.connect(_on_body_entered)
	# Kick it up and out in a random direction for the pop.
	var ang := randf() * TAU
	_vel = Vector3(cos(ang) * pop_side_speed, pop_up_speed, sin(ang) * pop_side_speed)
	await get_tree().process_frame
	_island = get_tree().get_first_node_in_group("island")
	get_tree().create_timer(arm_delay).timeout.connect(func() -> void: _armed = true)

func _process(delta: float) -> void:
	_time += delta
	rotate_y(spin_speed * delta)
	if _grounded:
		position.y = _base_y + sin(_time * bob_speed) * bob_height
		return
	# In-flight: integrate the arc until it reaches the ground, then settle.
	_vel.y -= drop_gravity * delta
	global_position += _vel * delta
	var ground := rest_height
	if _island and _island.has_method("height_at"):
		ground = _island.height_at(global_position.x, global_position.z) + rest_height
	if global_position.y <= ground and _vel.y <= 0.0:
		global_position.y = ground
		_grounded = true
		_base_y = position.y

func _on_body_entered(body: Node3D) -> void:
	if _armed and body.is_in_group("player"):
		Fx.poof(global_position, Color(0.75, 0.3, 1.0), 22, 1.1)
		Sfx.exotic()
		Game.collect_exotic()
		queue_free()

# Auto-scale an imported Meshy model to `target` meters and center it on the
# pickup's origin, so it spins/bobs about its middle no matter how it was exported.
func _fit_model(model: Node3D, target: float) -> void:
	if model == null:
		return
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var aabb: AABB
	var first := true
	var inv := model.global_transform.affine_inverse()
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := inv * mi.global_transform * mi.mesh.get_aabb()
		if first:
			aabb = local
			first = false
		else:
			aabb = aabb.merge(local)
	if first:
		return
	var biggest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if biggest <= 0.0:
		return
	var s := target / biggest
	model.scale = Vector3.ONE * s
	model.position = -aabb.get_center() * s
