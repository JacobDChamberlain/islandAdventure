extends Node3D
# A blaster pellet — a visible glowing orb that travels (Binding of Isaac tears,
# in 3D), rather than an instant hitscan. Built entirely in code (like the
# grapple rope and the lantern) so there's no .tscn to keep in sync; the weapon
# sets the exports, then adds it to the level.
#
# Movement is a SWEPT RAYCAST each frame, not an Area3D overlap. Two reasons:
# a pellet covers ~0.7 m per frame at 44 m/s, which is wider than it is, so
# overlap tests can miss thin walls entirely; and a ray reports the surface
# NORMAL, which is what the `bouncy` upgrade needs to bounce off things.

@export var speed: float = 42.0
@export var damage: int = 1
@export var knockback: float = 4.0
@export var radius: float = 0.22
@export var life: float = 2.5              # seconds before it fizzles out
@export var bounces: int = 0               # bounces left (0 = pops on first hit)
@export var color: Color = Color(0.55, 0.95, 1.0)

var dir: Vector3 = Vector3.FORWARD

var _t: float = 0.0
var _left: int = 0
var _last_hit: Object = null               # don't re-damage the same body twice running
var _ignore: Array[RID] = []

func _ready() -> void:
	_left = bounces
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Never collide with whoever fired it: the hero shares the world layer, and
	# the car is the gun platform when you're driving.
	for g in ["player", "vehicle"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is CollisionObject3D:
				_ignore.append(n.get_rid())

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	var step := speed * delta
	# Resolve the whole step, even if it takes several bounces in one frame.
	for _i in 4:
		if step <= 0.0:
			return
		var from := global_position
		var to := from + dir * step
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1 | 2          # world + heads
		q.collide_with_areas = false
		q.exclude = _ignore
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = to
			return
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var body = hit.get("collider")
		if body != null and body != _last_hit and body.has_method("hit_by_player"):
			body.hit_by_player(point, knockback, damage)
			Sfx.hit()
			_last_hit = body
		if _left <= 0:
			Fx.poof(point, color, 6, 0.4)
			queue_free()
			return
		# Ricochet: reflect, nudge clear of the surface, and spend the rest of
		# this frame's travel along the new heading.
		_left -= 1
		_last_hit = body
		step -= from.distance_to(point)
		dir = dir.bounce(normal).normalized()
		global_position = point + normal * (radius + 0.05)
		Fx.poof(point, color, 3, 0.25)
