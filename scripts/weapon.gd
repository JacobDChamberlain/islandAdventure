extends Node3D
# The hero's blaster. Bought from the cat, drawn with 1, fired by HOLDING the
# left mouse button — a continuous stream of visible pellets, not single shots.
# Hold Shift while it's drawn to scope in (narrow FOV + slower look).
#
# Fire behaviour lives entirely in MODES: an upgrade lying in the world just
# swaps which entry is active, so adding a new one is a new dictionary row.
#
# This is a plain Node3D the player builds in code (same as the lantern and the
# grapple rope), so any scene using player.gd gets it with no .tscn changes.

const BULLET := preload("res://scripts/bullet.gd")

# interval  seconds between shots      damage  per pellet
# speed     m/s                        spread  radians of random cone
# cost      ammo per shot              radius  pellet size (m)
const MODES := {
	"pellet": {
		"interval": 0.13, "damage": 1, "speed": 44.0, "spread": 0.022,
		"cost": 1, "radius": 0.22, "knockback": 4.0,
		"color": Color(0.55, 0.95, 1.0), "heavy_sound": false,
		"label": "BLASTER",
	},
	"rapid": {
		"interval": 0.055, "damage": 1, "speed": 52.0, "spread": 0.045,
		"cost": 1, "radius": 0.17, "knockback": 2.5,
		"color": Color(0.6, 1.0, 0.7), "heavy_sound": false,
		"label": "RAPID",
	},
	"laser": {
		"interval": 0.1, "damage": 1, "speed": 0.0, "spread": 0.0,
		"cost": 1, "radius": 0.14, "knockback": 1.5,
		"color": Color(1.0, 0.32, 0.48), "heavy_sound": false,
		"label": "LASER", "beam": true,
	},
	"bouncy": {
		"interval": 0.17, "damage": 1, "speed": 36.0, "spread": 0.02,
		"cost": 1, "radius": 0.26, "knockback": 3.0, "bounces": 4,
		"color": Color(0.85, 0.55, 1.0), "heavy_sound": false,
		"label": "BOUNCY",
	},
	"heavy": {
		"interval": 0.52, "damage": 4, "speed": 30.0, "spread": 0.0,
		"cost": 2, "radius": 0.62, "knockback": 13.0,
		"color": Color(1.0, 0.7, 0.35), "heavy_sound": true,
		"label": "HEAVY",
	},
}

@export var scope_fov: float = 42.0        # zoomed-in field of view
@export var normal_fov: float = 75.0
@export var scope_sensitivity: float = 0.45  # look speed multiplier while scoped
@export var muzzle_forward: float = 0.9
@export var muzzle_height: float = 0.7
@export var aim_distance: float = 220.0    # how far the crosshair ray reaches

# --- The visible gun in his hand ------------------------------------------
# Meshy bakes a ~100x scale into the hero's rig, so a model parented to a hand
# bone inherits that: the fit below divides it back out using the bone's real
# world scale, and `gun_length` is a true world-space measurement in metres.
@export var gun_model: PackedScene = preload("res://assets/models/gun_eyeball.glb")
@export var gun_bone: String = "RightHand"
@export var gun_length: float = 0.84        # longest axis, in real metres
@export var gun_offset: Vector3 = Vector3.ZERO      # nudge into the grip, in metres
@export var gun_rotation_deg: Vector3 = Vector3.ZERO
# Which way the MODEL points in its own space. Meshy exports land in arbitrary
# orientations, so instead of hand-tuning Euler angles we say which local axis is
# the barrel and which is "up", and the fit rotates that onto the hero's aim.
@export var gun_barrel_axis: Vector3 = Vector3(-1, 0, 0)
@export var gun_up_axis: Vector3 = Vector3(0, 1, 0)

var drawn: bool = false
var scoped: bool = false

var _cooldown: float = 0.0
var _player: CharacterBody3D
var _camera: Camera3D
var _beam: MeshInstance3D          # the laser's visible tube (built like the grapple rope)
var _beam_sound: float = 0.0       # throttles the sizzle so it isn't machine-gunned
var _hand: BoneAttachment3D        # follows the hero's hand bone
var _gun: Node3D                   # the visible weapon model
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_player = get_parent() as CharacterBody3D
	_camera = _player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if _camera:
		normal_fov = _camera.fov
	_build_beam()
	_setup_gun_visual()

func _build_beam() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 1.0
	cyl.radial_segments = 8
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.top_level = true          # positioned in world space, like the grapple rope
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.32, 0.48)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.32, 0.48)
	mat.emission_energy_multiplier = 9.0
	_beam.material_override = mat
	_beam.visible = false
	add_child(_beam)

# Hang the gun off the hero's hand bone. It only shows while the gun is drawn,
# so holstering genuinely puts it away.
func _setup_gun_visual() -> void:
	if gun_model == null or _player == null:
		return
	var model: Node3D = _player.get("model")
	if model == null:
		return
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	_hand = BoneAttachment3D.new()
	_hand.bone_name = gun_bone
	skels[0].add_child(_hand)
	_gun = gun_model.instantiate()
	_hand.add_child(_gun)
	_gun.visible = false
	await get_tree().process_frame     # wait for the skeleton to pose
	_fit_gun()

func _fit_gun() -> void:
	if _gun == null or not is_instance_valid(_gun):
		return
	var box := AABB()
	var first := true
	for child in _gun.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0:
		return
	# Divide out the rig's baked scale so gun_length/gun_offset mean real metres.
	var bone_scale: float = maxf(_hand.global_transform.basis.get_scale().x, 0.0001)
	var s: float = gun_length / (longest * bone_scale)

	# Orient it properly instead of leaving it flat in his palm. The hand bone's
	# axes are arbitrary, so rather than hand-guessing Euler angles we compute the
	# local rotation that lands the model's long axis along the hero's forward
	# (where the reticle points) and its tall axis along world up.
	var p_inv := _player.global_transform.affine_inverse()
	var bone_in_player := (p_inv * _hand.global_transform).basis.orthonormalized()
	# Rotation that carries the model's own barrel/up axes onto the hero's
	# forward/up (forward = -Z, which is exactly where the reticle points).
	var b := gun_barrel_axis.normalized()
	var m := gun_up_axis.normalized()
	var model_frame := Basis(b, m, b.cross(m))
	var aim_frame := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(0, 0, -1).cross(Vector3(0, 1, 0)))
	var align := aim_frame * model_frame.inverse()
	var local := bone_in_player.inverse() * align
	local = local * Basis.from_euler(gun_rotation_deg * (PI / 180.0))
	_gun.transform = Transform3D(local.scaled(Vector3.ONE * s), gun_offset / bone_scale)

# While driving, the car is the gun platform: its chase camera aims and the
# muzzle rides on the car, since the hero himself is hidden inside it.
func _rig() -> Node3D:
	if Game.driving:
		var v := get_tree().get_first_node_in_group("vehicle") as Node3D
		if v != null:
			return v
	return _player

func _aim_camera() -> Camera3D:
	if Game.driving:
		var v := get_tree().get_first_node_in_group("vehicle")
		if v != null:
			var vc := v.get_node_or_null("ChaseCam") as Camera3D
			if vc != null:
				return vc
	return _camera

func mode() -> Dictionary:
	return MODES.get(Game.weapon_mode, MODES["pellet"])

func mode_label() -> String:
	return mode()["label"]

# The gun is only usable once bought, and never during a scripted moment.
func _blocked() -> bool:
	return Dialogue.active or Game.cinematic \
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

func is_active() -> bool:
	return Game.has_gun and drawn and not _blocked()

func toggle_drawn() -> void:
	if not Game.has_gun:
		return
	drawn = not drawn
	Sfx.ui_select()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_1:
		toggle_drawn()

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

	if _gun != null and is_instance_valid(_gun):
		_gun.visible = Game.has_gun and drawn and _player.visible \
			and not (_player.has_method("is_attacking") and _player.is_attacking())

	# Scope: pull the FOV in while Shift is held with the gun out.
	scoped = is_active() and Input.is_physical_key_pressed(KEY_SHIFT)
	scoped = scoped and not Game.driving      # no scoping from the driver's seat
	if _camera:
		var want := scope_fov if scoped else normal_fov
		_camera.fov = lerpf(_camera.fov, want, 1.0 - pow(0.002, delta))

	# Hold to fire — the whole point of the stream.
	var holding := is_active() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if bool(mode().get("beam", false)):
		_beam_step(delta, holding)
		return
	_beam.visible = false
	if holding and _cooldown <= 0.0:
		_fire()

# --- Laser -------------------------------------------------------------------
# A held beam instead of projectiles: raycast every frame, stretch the tube to
# whatever it hits, and apply damage on the mode's interval rather than per shot.

func _beam_step(delta: float, holding: bool) -> void:
	if not holding:
		_beam.visible = false
		return
	var m := mode()
	var origin := _muzzle()
	var target := _aim_point()
	var dir := (target - origin)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * aim_distance)
	q.collision_mask = 1 | 2
	q.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if not hit.is_empty() else origin + dir * aim_distance
	_stretch_beam(origin, end)

	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if not Game.spend_ammo(int(m["cost"])):
		Sfx.dry_fire()
		_beam.visible = false
		_cooldown = 0.35
		return
	_cooldown = float(m["interval"])
	var body = hit.get("collider") if not hit.is_empty() else null
	if body != null and body.has_method("hit_by_player"):
		body.hit_by_player(end, float(m["knockback"]), int(m["damage"]))
		Fx.poof(end, m["color"], 4, 0.3)
	_beam_sound -= m["interval"]
	if _beam_sound <= 0.0:
		_beam_sound = 0.18                # sizzle, not a machine gun
		Sfx.shoot()

func _stretch_beam(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var length := span.length()
	if length < 0.05:
		_beam.visible = false
		return
	var y_axis := span / length
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	_beam.global_transform = Transform3D(
		Basis(x_axis, y_axis, z_axis).scaled(Vector3(1.0, length, 1.0)), (from + to) * 0.5)
	_beam.visible = true

func _fire() -> void:
	var m := mode()
	if not Game.spend_ammo(int(m["cost"])):
		Sfx.dry_fire()
		_cooldown = 0.35        # click, don't machine-gun the empty sound
		return
	_cooldown = float(m["interval"])

	var origin := _muzzle()
	var to := _aim_point()
	var dir := (to - origin)
	if dir.length() < 0.01:
		dir = -_player.global_transform.basis.z
	dir = dir.normalized()
	# Scoping tightens the cone to nothing; hip fire sprays.
	var spread := float(m["spread"]) * (0.25 if scoped else 1.0)
	if spread > 0.0:
		dir = dir.rotated(Vector3.UP, _rng.randf_range(-spread, spread))
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() > 0.01:
			dir = dir.rotated(side, _rng.randf_range(-spread, spread))

	var b = BULLET.new()
	b.dir = dir
	b.speed = m["speed"]
	b.damage = m["damage"]
	b.knockback = m["knockback"]
	b.radius = m["radius"]
	b.color = m["color"]
	b.bounces = int(m.get("bounces", 0))
	# Parent to the level, not the player, so pellets don't ride along with him.
	var level := _player.get_parent()
	level.add_child(b)
	b.global_position = origin

	if bool(m["heavy_sound"]):
		Sfx.shoot_heavy()
	else:
		Sfx.shoot()

func _muzzle() -> Vector3:
	var rig := _rig()
	var fwd := -rig.global_transform.basis.z
	return rig.global_position + Vector3.UP * muzzle_height + fwd * muzzle_forward

# Where the crosshair is pointing: the first thing the centre-screen ray hits,
# or a far point in the sky. Shooting at this (rather than straight ahead) is
# what makes the pellets land where the reticle is.
func _aim_point() -> Vector3:
	var cam := _aim_camera()
	if cam == null:
		var rig := _rig()
		return rig.global_position - rig.global_transform.basis.z * aim_distance
	var centre := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(centre)
	var to := from + cam.project_ray_normal(centre) * aim_distance
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 2 | 4
	q.collide_with_areas = false
	q.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else to
