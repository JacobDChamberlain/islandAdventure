extends CharacterBody3D
# This is the player character. Right now it's a plain capsule (a "greybox"
# placeholder). Later we'll swap the capsule mesh for your Meshy.ai hero model,
# and this same movement code keeps working.

@export var speed: float = 11.0          # how fast you run
@export var jump_velocity: float = 15.0  # how high you jump
@export var gravity: float = 38.0        # how hard you fall (higher = snappier, less floaty)
@export var max_jumps: int = 2           # 2 = double jump
@export var mouse_sensitivity: float = 0.0025

# --- Third-person camera (pulls in when something blocks the view) ---
@export var cam_distance: float = 5.0
@export var cam_height: float = 1.5
@export var cam_dialogue_distance: float = 2.6   # zoom-in distance while talking
@export var cam_dialogue_height: float = 1.2
var _cam_frac: float = 1.0   # 0..1 of the ideal distance, smoothed
var _cine_blend: float = 0.0 # 0..1 toward the zoomed-in conversation framing

# --- How quickly speed changes (higher = snappier). Ground is tight; air keeps
#     your momentum so a jump commits you to an arc instead of stopping dead. ---
@export var ground_accel: float = 90.0   # speeding up while on the ground
@export var ground_decel: float = 90.0   # stopping while on the ground
@export var air_accel: float = 25.0      # steering ("air control") mid-jump
@export var air_decel: float = 8.0       # how fast you taper off after releasing in the air

# --- Combat / hits ---
@export var bounce_velocity: float = 14.0    # upward pop after stomping an enemy
@export var knockback_strength: float = 10.0 # how hard a hit shoves you away
@export var invuln_time: float = 1.0         # seconds of "can't be hit" after a hit

# --- Melee attacks (punch / kick) ---
@export var attack_damage: int = 1
@export var punch_knockback: float = 9.0      # how hard a punch shoves an enemy
@export var kick_knockback: float = 15.0      # kicks hit harder / knock further
# Wind-up = delay before the hit lands, tuned to when each clip actually connects.
@export var punch_windup: float = 0.15
@export var kick_windup: float = 0.14
@export var flying_kick_windup: float = 0.16
@export var attack_cooldown: float = 0.32     # min time between attacks
@export var punch_anim_speed: float = 2.0       # snappier punches
@export var kick_anim_speed: float = 1.7        # snappier kick
@export var kick_anim_start: float = 0.12       # skip this much of the kick's wind-up

# --- Visual model (the imported Meshy hero) ---
@export var model_target_height: float = 1.9    # how tall the hero should appear (world units)
@export var model_yaw_offset_deg: float = 180.0 # spin the model if it faces the wrong way
@export var model_y_offset: float = 0.0         # nudge up/down if feet sink or float

# --- Sprint (double-tap W and hold) ---
@export var sprint_speed: float = 20.0     # speed while sprinting
@export var double_tap_window: float = 0.3 # max seconds between the two W taps

# --- Lantern (L): the hero lights himself up so you can see at night ---
@export var lantern_color: Color = Color(1.0, 0.86, 0.6)  # warm lamp light
@export var lantern_range: float = 36.0     # how far the cast light reaches
@export var lantern_energy: float = 9.0     # brightness of the cast light
@export var lantern_height: float = 1.35    # see _setup_lantern — must clear his head
@export var lantern_glow: float = 1.1       # how brightly the model itself glows
@export var lantern_shadows: bool = true    # light gets blocked by walls/terrain

# --- Grapple hook (Q / middle-mouse): fire at a surface, reel up onto roofs ---
@export var can_grapple: bool = false            # gated per-level (city on); later a 25-coin shop unlock
@export var grapple_range: float = 48.0          # how far the hook can reach
@export var grapple_reel_speed: float = 34.0     # how fast you're pulled to the anchor
@export var grapple_release_dist: float = 3.0    # let go once this close to the anchor
@export var grapple_release_pop: float = 13.0    # upward pop on release so you crest the ledge
@export var grapple_max_time: float = 2.5        # safety auto-release if we jam on a wall

# --- Animation clip names (must match the clips baked into the .glb) ---
@export var anim_idle: String = "Idle_6"
@export var anim_run: String = "Running"
@export var anim_run_fast: String = "RunFast"
@export var anim_jump: String = "Jump_with_Arms_Open"
@export var anim_sprint_jump: String = "Run_and_Jump"
# Combat / emote clips (baked into hero_anim_merged.glb). Empty = the mechanic
# still works, just without a bespoke animation.
@export var anim_punch: String = "Punch_Combo_1"
@export var anim_punch2: String = "Punch_Combo"       # alternated for a combo feel
@export var anim_kick: String = "High_Kick"            # grounded kick
@export var anim_flying_kick: String = "Rising_Flying_Kick"  # kick while airborne
@export var anim_death: String = "Dead"
@export var anim_hit: String = "Hit_Reaction"          # played when you take a hit
@export var anim_dance: String = "All_Night_Dance"     # G
@export var anim_dance2: String = "Breakdance_1990"    # H
@export var jump_anim_speed: float = 1.6   # play the jump clip faster so it reads
@export var jump_anim_start: float = 0.25  # skip this many seconds of jump wind-up
@export var sprint_jump_anim_speed: float = 1.5 # speed of the sprint run-and-jump
@export var sprint_jump_anim_start: float = 0.2 # skip this much of its lead-in
@export var roll_slide_speed: float = 14.0      # forward speed when landing the roll
@export var roll_slide_decel: float = 9.0        # how quickly the roll slide tapers

var anim: AnimationPlayer
var _current_anim: String = ""
var _anim_locked: bool = false   # true while a one-shot (sprint-jump) plays fully
var _rolling: bool = false       # true during the forward slide of the landing roll
var _sj_airborne: bool = false   # have we actually left the ground this sprint-jump?
var _sprinting: bool = false
var _last_w_time: float = -999.0
var jumps_left: int = 2
var _step_timer: float = 0.0
var _invuln: float = 0.0
var _spawn_point: Vector3 = Vector3.ZERO
var _attacking: bool = false
var _dancing: bool = false
var _punch_toggle: bool = false   # alternate the two punch clips

# --- Lantern state ---
var _lantern: OmniLight3D
var _lantern_on: bool = false
var _lantern_t: float = 0.0
# One entry per mesh surface: the material it normally wears, and a glowing copy
# we swap in only while the lantern is lit.
var _glow_slots: Array[Dictionary] = []

# --- Grapple state ---
var _grappling: bool = false
var _grapple_point: Vector3 = Vector3.ZERO
var _grapple_target: Node3D = null   # set when hooked onto a (moving) kaiju
var _grapple_time: float = 0.0

# --- Vehicle ---
var _driving: bool = false
var _saved_layer: int = 1
var _saved_mask: int = 1
var _rope: MeshInstance3D
var _reticle: Label
var weapon: Node3D          # the blaster (scripts/weapon.gd), built in code

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var model: Node3D = get_node_or_null("Model")
@onready var attack_hitbox: Area3D = get_node_or_null("AttackHitbox")

func _ready() -> void:
	jumps_left = max_jumps
	_spawn_point = global_position
	add_to_group("player")   # so gems and enemies can recognize us
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	# Treat steep hillsides as walkable floor (island has slopes to climb), and
	# stick to the ground over bumps instead of launching off every rise.
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.6
	# Lock the mouse to the window so moving it turns the camera.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Tilt the camera down slightly for a nice third-person angle.
	camera.rotation_degrees.x = -12.0
	# Auto-scale and plant the hero model so it fits the collision capsule.
	_fit_model()
	_setup_animation()
	_setup_grapple_visuals()
	_setup_lantern()
	_setup_weapon()
	_snap_to_ground()

func _snap_to_ground() -> void:
	# Place exactly on the terrain using the island's own height function — no
	# raycast (which can miss before collision is ready and cause a fall loop).
	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		global_position.y = island.height_at(global_position.x, global_position.z) + 3.0
		velocity = Vector3.ZERO
	_spawn_point = global_position

# --- Lantern -----------------------------------------------------------------
# Press L and the hero himself becomes the light source: a warm omni light at
# chest height, plus his own materials switched to emissive so he visibly glows
# instead of just projecting light out of nowhere. Built in code (like the
# grapple visuals) so it rides along with every scene that uses this script.

func _setup_lantern() -> void:
	_lantern = OmniLight3D.new()
	_lantern.light_color = lantern_color
	_lantern.light_energy = lantern_energy
	_lantern.omni_range = lantern_range
	_lantern.omni_attenuation = 0.8
	_lantern.shadow_enabled = lantern_shadows
	# The light MUST sit above his head, not inside his chest. A shadow-casting
	# omni light placed inside the hero's own mesh is boxed in by that mesh in
	# every direction, so nothing around him lights up — he glows and the world
	# stays black. Clearing the model lets it light the ground, trees and walls
	# and cast a proper shadow of him.
	_lantern.position = Vector3(0.0, lantern_height, 0.0)
	_lantern.visible = false
	add_child(_lantern)
	_collect_glow_materials()

# Build a glowing COPY of each of the hero's materials, but leave it unapplied —
# `_toggle_lantern` swaps it in and back out. We never modify the material he
# normally wears: the Meshy hero ships with emission already enabled (a black
# emission color ADDed over an emissive texture), and touching that changes how
# he looks unlit — disabling it let his metallic=1.0 highlights read as "shiny".
func _collect_glow_materials() -> void:
	if model == null:
		return
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			# What he wears normally — usually null, meaning "use the mesh's own".
			var original: Material = mi.get_surface_override_material(i)
			var src: Material = original if original != null else mi.mesh.surface_get_material(i)
			if not (src is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = src.duplicate()
			mat.emission_enabled = true
			mat.emission = lantern_color
			mat.emission_energy_multiplier = lantern_glow
			# Drive the glow through his own texture so he keeps his details and
			# doesn't turn into a flat glowing blob.
			if mat.albedo_texture:
				mat.emission_texture = mat.albedo_texture
				mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			_glow_slots.append({"mi": mi, "surf": i, "original": original, "glow": mat})

func _toggle_lantern() -> void:
	if _lantern == null:
		return
	_lantern_on = not _lantern_on
	_lantern.visible = _lantern_on
	# Swapping the whole material back restores his imported look exactly.
	for s in _glow_slots:
		var mi: MeshInstance3D = s["mi"]
		mi.set_surface_override_material(s["surf"], s["glow"] if _lantern_on else s["original"])
	Sfx.ui_select()

# Enemies ask this — a lit hero scares the nightmare heads off. True while
# driving too: the car carries the lamp on its roof, and the hidden hero rides
# at the car's own position, so the heads flee the car exactly as they would him.
func lantern_is_on() -> bool:
	return _lantern_on

# The weapon hides the gun model during punches/kicks — he has no aim animation,
# so a pistol riding through a haymaker looks wrong.
func is_attacking() -> bool:
	return _attacking

# Any melee moment the gun should sit out: his own punches/kicks, plus the hit
# reaction and death clips — a pistol held through those reads badly.
func is_busy_melee() -> bool:
	if _attacking:
		return true
	return _anim_locked and (_current_anim == anim_hit or _current_anim == anim_death)

# L lives here rather than in _input because _input bails out while driving, and
# the lantern should still toggle from the driver's seat.
func _unhandled_input(event: InputEvent) -> void:
	if Dialogue.active or Game.cinematic:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_L:
		_toggle_lantern()

func _process(delta: float) -> void:
	# In _process, not _physics_process: the car switches physics off on the hero
	# and we still want the crosshair while you're shooting from the driver's seat.
	_update_reticle()
	if not _lantern_on or _lantern == null:
		return
	# Gentle breathing so the glow feels alive instead of a flat spotlight.
	_lantern_t += delta
	var pulse := 0.92 + 0.08 * sin(_lantern_t * 2.4)
	_lantern.light_energy = lantern_energy * pulse
	for s in _glow_slots:
		s["glow"].emission_energy_multiplier = lantern_glow * pulse

# --- Blaster -----------------------------------------------------------------

func _setup_weapon() -> void:
	weapon = load("res://scripts/weapon.gd").new()
	weapon.name = "Weapon"
	add_child(weapon)

# True when the blaster is out, so melee and the crosshair can defer to it.
func _gun_out() -> bool:
	return weapon != null and weapon.is_active()

# --- Grapple hook ------------------------------------------------------------
# A rope (world-space line) + a center-screen crosshair, both built in code so
# they ride along with any player scene without editing the .tscn.

func _setup_grapple_visuals() -> void:
	# The rope is a unit-height cylinder we stretch/orient between hand and anchor
	# each frame — a thick, bright, glowing tube (lines can't be made thick).
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 1.0
	cyl.radial_segments = 8
	_rope = MeshInstance3D.new()
	_rope.mesh = cyl
	_rope.top_level = true   # draw in world coordinates, not relative to the player
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 1.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 1.0, 0.5)
	mat.emission_energy_multiplier = 8.0
	_rope.material_override = mat
	_rope.visible = false
	add_child(_rope)

	var layer := CanvasLayer.new()
	add_child(layer)
	_reticle = Label.new()
	_reticle.text = "+"
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.add_theme_font_size_override("font_size", 30)
	_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_reticle)

# Ray from the center of the screen out to grapple_range (world, terrain/buildings).
func _aim_ray() -> Dictionary:
	if camera == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(center)
	var to := from + camera.project_ray_normal(center) * grapple_range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 4            # world geometry (layer 1) + kaiju (layer 3)
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

# Grapple works if the scene grants it (can_grapple) OR it's been bought (persists).
func _grapple_enabled() -> bool:
	return can_grapple or Game.has_grapple

func _fire_grapple() -> void:
	if not _grapple_enabled() or _grappling or _attacking or Dialogue.active or Game.cinematic:
		return
	var hit := _aim_ray()
	if hit.is_empty():
		return
	var p: Vector3 = hit.position
	if global_position.distance_to(p) < grapple_release_dist:
		return                          # basically at our feet — ignore
	_grapple_target = null
	var collider = hit.get("collider")
	if collider and collider is Node and collider.is_in_group("enemy"):
		# Hooked a kaiju: track it (it moves) and aim just above its crown, so the
		# reel carries us up and we drop onto its head for the stomp.
		_grapple_target = collider
	else:
		# If we hit a building's SIDE, retarget the anchor to a point on its ROOFTOP
		# (just inside the near edge) so the reel pulls us up and over, instead of
		# dragging us into the wall.
		var ground := get_tree().get_first_node_in_group("island")
		if ground and ground.has_method("building_top_at"):
			var roof: float = ground.building_top_at(p.x, p.z)
			if roof > p.y + 1.0:
				var into := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
				if into.length() > 0.01:
					into = into.normalized()
				p = Vector3(p.x, roof + 1.5, p.z) + into * 5.0   # a few meters onto the roof
	_grapple_point = p
	_grappling = true
	_grapple_time = 0.0
	_cancel_dance()
	if _grapple_target:
		_track_grapple_target()
	_rope.visible = true
	_update_rope()
	Sfx.jump()

# Aim the anchor just above a hooked kaiju's head, following it as it moves.
func _track_grapple_target() -> void:
	if not is_instance_valid(_grapple_target):
		return
	var half := 1.3
	if "model_height" in _grapple_target:
		half = _grapple_target.model_height * 0.5 * _grapple_target.global_transform.basis.get_scale().y
	_grapple_point = _grapple_target.global_position + Vector3.UP * (half + 1.5)

func _end_grapple(pop: bool) -> void:
	if not _grappling:
		return
	_grappling = false
	_grapple_target = null
	_rope.visible = false
	if pop:
		velocity.y = maxf(velocity.y, grapple_release_pop)
		jumps_left = max_jumps          # like a launch pad: refill air-jumps

# Reel toward the anchor each frame; release (with an upward pop) on arrival,
# on landing, or after the safety timeout if we jam against a wall.
func _grapple_step(delta: float) -> void:
	_grapple_time += delta
	# Follow a hooked kaiju (it walks around) — or bail if it died mid-swing.
	if _grapple_target != null:
		if not is_instance_valid(_grapple_target):
			_end_grapple(true)
			return
		_track_grapple_target()
	var to_point := _grapple_point - global_position
	if to_point.length() <= grapple_release_dist or _grapple_time >= grapple_max_time:
		_end_grapple(true)
	else:
		velocity = to_point.normalized() * grapple_reel_speed
		move_and_slide()
		if is_on_floor():
			_end_grapple(true)
		else:
			_update_rope()
	_update_animation()
	_update_camera(delta)

func _update_rope() -> void:
	if _rope == null:
		return
	var start := global_position + Vector3.UP + (-transform.basis.z) * 0.3
	var to_end := _grapple_point - start
	var length := to_end.length()
	if length < 0.05:
		return
	var y_axis := to_end / length
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis).scaled(Vector3(1.0, length, 1.0))
	_rope.global_transform = Transform3D(basis, (start + _grapple_point) * 0.5)

# Crosshair: dim white normally, green when a valid anchor is in range.
func _update_reticle() -> void:
	if _reticle == null:
		return
	var show := (_grapple_enabled() or _gun_out()) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not Dialogue.active and not Game.cinematic
	_reticle.visible = show
	if not show:
		return
	if _gun_out():
		_reticle.modulate = Color(1.0, 0.85, 0.45, 0.95) if Game.ammo > 0 else Color(1.0, 0.4, 0.4, 0.8)
		return
	var hot := _grappling or not _aim_ray().is_empty()
	_reticle.modulate = Color(0.5, 1.0, 0.6, 0.95) if hot else Color(1, 1, 1, 0.5)

func _setup_animation() -> void:
	if model == null:
		return
	anim = model.get_node_or_null("AnimationPlayer")
	if anim == null:
		return
	# Looping locomotion clips.
	for clip in [anim_idle, anim_run, anim_run_fast]:
		if anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	# One-shot clips that should play through and stop (not loop).
	for clip in [anim_jump, anim_sprint_jump, anim_punch, anim_punch2, anim_kick, anim_flying_kick, anim_death, anim_hit]:
		if anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	_strip_root_motion()
	anim.animation_finished.connect(_on_anim_finished)

func _strip_root_motion() -> void:
	# Freeze every bone POSITION track to its first frame so clips play "in place".
	# Some Meshy clips (the jumps) bake forward travel into the root bone's position,
	# which made the hero drift forward then snap back. With translation removed, he
	# only ever moves via the code-driven velocity — his real momentum.
	for clip_name in anim.get_animation_list():
		var a := anim.get_animation(clip_name)
		for ti in a.get_track_count():
			if a.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			var kc := a.track_get_key_count(ti)
			if kc == 0:
				continue
			var base: Vector3 = a.track_get_key_value(ti, 0)
			for k in range(1, kc):
				a.track_set_key_value(ti, k, base)

func _on_anim_finished(finished_name: String) -> void:
	# When a locked one-shot (the sprint-jump) ends, release the lock so the
	# normal state machine takes over again.
	if _anim_locked and finished_name == _current_anim:
		_anim_locked = false
		_current_anim = ""

func _play_oneshot(clip: String, speed: float = 1.0, start: float = 0.0) -> void:
	# Play a clip fully, ignoring state changes until it finishes.
	if anim == null or not anim.has_animation(clip):
		return
	anim.play(clip, 0.1, speed)
	if start > 0.0:
		anim.seek(start, true)
	_current_anim = clip
	_anim_locked = true

func _update_animation() -> void:
	if anim == null or _anim_locked:
		return
	var desired := anim_idle
	if not is_on_floor():
		desired = anim_jump
	elif Vector2(velocity.x, velocity.z).length() > 0.6:
		desired = anim_run_fast if _sprinting else anim_run
	if desired == _current_anim or not anim.has_animation(desired):
		return
	if desired == anim_jump:
		# Speed it up and skip the wind-up so the leap actually shows on a short hop.
		anim.play(desired, 0.05, jump_anim_speed)
		anim.seek(jump_anim_start, true)
	else:
		anim.play(desired, 0.15)
	_current_anim = desired

func _fit_model() -> void:
	if model == null:
		return
	var aabb := _fit_aabb()
	if aabb.size.y <= 0.0:
		return
	var s := model_target_height / aabb.size.y
	model.scale = Vector3.ONE * s
	# Plant the feet at the bottom of the capsule collision (y = -1 in local space).
	# (Rotating about Y doesn't affect height, so this stays correct at any yaw.)
	model.position = Vector3(0.0, -1.0 - aabb.position.y * s + model_y_offset, 0.0)
	model.rotation_degrees.y = model_yaw_offset_deg

func _fit_aabb() -> AABB:
	# For a rigged model, measure the SKELETON's true extent. The mesh's own AABB
	# is stored in bind-pose space and ignores bone scaling (Meshy bakes a ~100x
	# scale into the rig), which otherwise makes the character wildly oversized.
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
	return _mesh_aabb()

func _mesh_aabb() -> AABB:
	# Fallback for un-rigged models: combined bounding box of every mesh.
	var result := AABB()
	var first := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_model := model.global_transform.affine_inverse() * mi.global_transform
		var box := to_model * mi.mesh.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result

func _try_jump() -> void:
	_cancel_dance()
	if jumps_left > 0:
		velocity.y = jump_velocity
		jumps_left -= 1
		Sfx.jump()
		# Jumping while sprinting on the ground plays the full run-and-jump clip.
		if _sprinting and is_on_floor():
			_play_oneshot(anim_sprint_jump, sprint_jump_anim_speed, sprint_jump_anim_start)

# Called by an enemy when you stomp its head: pop upward and regain an air-jump.
func bounce() -> void:
	velocity.y = bounce_velocity
	jumps_left = max_jumps - 1

# Called by a launch pad: fling upward and refill jumps.
func launch(strength: float) -> void:
	velocity.y = strength
	jumps_left = max_jumps
	Sfx.jump()

# Melee attack. `kind` is "punch" or "kick". Kicks in the air become a flying
# kick; punches are grounded only. Plays the clip, waits a wind-up, then hits
# every enemy inside the AttackHitbox once.
func _attack(kind: String) -> void:
	if _attacking:
		return
	var airborne := not is_on_floor()
	var is_kick := kind == "kick"
	if not is_kick and airborne:
		return   # no air-punch; only kicks work airborne
	_cancel_dance()
	_attacking = true
	var flying := is_kick and airborne
	var kb := punch_knockback
	var clip := ""
	var spd := punch_anim_speed
	var windup := punch_windup
	var start := 0.0
	if flying:
		kb = kick_knockback * 1.3      # flying kick hits hardest
		clip = anim_flying_kick
		spd = kick_anim_speed
		windup = flying_kick_windup
	elif is_kick:
		kb = kick_knockback
		clip = anim_kick
		spd = kick_anim_speed
		windup = kick_windup
		start = kick_anim_start        # skip the slow wind-up frames
	else:
		# Alternate the two punch clips for a light combo feel.
		clip = anim_punch2 if _punch_toggle else anim_punch
		_punch_toggle = not _punch_toggle
		windup = punch_windup
	if clip != "" and anim and anim.has_animation(clip):
		_play_oneshot(clip, spd, start)
	await get_tree().create_timer(windup).timeout
	if not is_inside_tree():
		return
	var hit_any := false
	if attack_hitbox:
		for b in attack_hitbox.get_overlapping_bodies():
			if b.has_method("hit_by_player"):
				b.hit_by_player(global_position, kb, attack_damage)
				hit_any = true
	if hit_any:
		Sfx.hit()
	await get_tree().create_timer(attack_cooldown).timeout
	if not is_inside_tree():
		return
	_attacking = false

# Toggle a dance emote (only while idle on the ground). Any movement cancels it.
func _toggle_dance(clip: String) -> void:
	if _attacking or not is_on_floor():
		return
	if _dancing:
		_cancel_dance()
		return
	if clip == "" or anim == null or not anim.has_animation(clip):
		return
	_dancing = true
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play(clip, 0.15)
	_current_anim = clip
	_anim_locked = true

func _cancel_dance() -> void:
	if _dancing:
		_dancing = false
		_anim_locked = false
		_current_anim = ""

# Called by an enemy when it hits you from the side.
func take_hit(source_pos: Vector3) -> void:
	if _invuln > 0.0 or _driving:
		return   # invincible right after a hit, or safe inside the car
	_invuln = invuln_time
	Sfx.hurt()
	_cancel_dance()
	if anim_hit != "" and anim and anim.has_animation(anim_hit):
		_play_oneshot(anim_hit, 1.3)
	# Shove away from whatever hit us, plus a little upward pop.
	var away := global_position - source_pos
	away.y = 0.0
	away = away.normalized()
	velocity.x = away.x * knockback_strength
	velocity.z = away.z * knockback_strength
	velocity.y = bounce_velocity * 0.6
	if Game.damage(1):
		_handle_death()

# Lose a life and respawn — unless that was the last life (then Game emits
# game_over and the end screen takes over, so we just stop).
func _handle_death() -> void:
	_cancel_dance()
	if anim_death != "" and anim and anim.has_animation(anim_death):
		_play_oneshot(anim_death, 1.0)
	if Game.lose_life():
		return
	global_position = _spawn_point
	velocity = Vector3.ZERO
	_invuln = invuln_time

# --- Vehicle: hide + disable the hero while it drives; the vehicle drives the
#     camera. The vehicle calls these when you press E to get in / out.

func board_vehicle() -> void:
	_driving = true
	velocity = Vector3.ZERO
	visible = false
	set_physics_process(false)
	collision_layer = 0          # so the moving car can't hit the parked hero
	collision_mask = 0
	if _grappling:
		_end_grapple(false)
	if _reticle:
		_reticle.visible = false

func unboard_vehicle(world_pos: Vector3) -> void:
	global_position = world_pos
	velocity = Vector3.ZERO
	visible = true
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	set_physics_process(true)
	_driving = false
	if camera:
		camera.current = true

func _input(event: InputEvent) -> void:
	# Frozen during a scripted moment (dialogue box, the Elder's finale, driving).
	if Dialogue.active or Game.cinematic or _driving:
		return
	# Mouse look: horizontal turns the whole body, vertical tilts only the camera.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * Settings.sensitivity
		if weapon and weapon.scoped:
			sens *= weapon.scope_sensitivity
		rotate_y(-event.relative.x * sens)
		camera_pivot.rotate_x(-event.relative.y * sens)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-70), deg_to_rad(80))
	# Click to recapture the mouse (e.g. after unpausing). Esc is handled by the
	# pause menu, not here.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# While playing (mouse captured): left click punches, right click kicks.
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _gun_out():          # gun out = LMB shoots (weapon.gd polls the hold)
				_attack("punch")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_attack("kick")
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_fire_grapple()
	# Keyboard alternatives: J punch, K kick, G/H dance, Q grapple, L lantern.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_J: _attack("punch")
			KEY_K: _attack("kick")
			KEY_G: _toggle_dance(anim_dance)
			KEY_H: _toggle_dance(anim_dance2)
			KEY_Q: _fire_grapple()
	# Jump on the moment Space is pressed (not while held), so double-jump works.
	# Space while grappling lets go early (with the launch pop).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		if _grappling:
			_end_grapple(true)
		else:
			_try_jump()
	# Double-tap W (then keep it held) to sprint.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_W:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_w_time <= double_tap_window:
			_sprinting = true
		_last_w_time = now

func _physics_process(delta: float) -> void:
	# Count down invulnerability after a hit.
	if _invuln > 0.0:
		_invuln -= delta

	# A scripted moment starting mid-swing cancels the grapple (no upward pop).
	if (Dialogue.active or Game.cinematic) and _grappling:
		_end_grapple(false)

	# Grappling overrides normal movement: reel toward the anchor.
	if _grappling:
		_grapple_step(delta)
		return

	# Frozen in place while talking to an NPC (or during the Elder's finale).
	if Dialogue.active or Game.cinematic:
		velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_decel * delta)
		velocity.y = velocity.y - gravity * delta if not is_on_floor() else 0.0
		move_and_slide()
		_update_animation()
		return

	# Refill jumps only while genuinely resting on the ground (not on the way up).
	if is_on_floor() and velocity.y <= 0.0:
		jumps_left = max_jumps

	# Gravity pulls you down whenever you're in the air.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Releasing W ends the sprint.
	if not Input.is_physical_key_pressed(KEY_W):
		_sprinting = false

	# Sprint-jump landing roll: once we've actually been airborne and then touch
	# down, launch a committed forward slide so the roll travels instead of
	# spinning in place. It tapers off on its own.
	var in_sprint_jump := _anim_locked and _current_anim == anim_sprint_jump
	if in_sprint_jump and not is_on_floor():
		_sj_airborne = true
	if in_sprint_jump and _sj_airborne and is_on_floor() and not _rolling:
		_rolling = true
		var fwd := -transform.basis.z
		velocity.x = fwd.x * roll_slide_speed
		velocity.z = fwd.z * roll_slide_speed
	if not in_sprint_jump:
		_rolling = false
		_sj_airborne = false

	# Read WASD into a direction, relative to the way you're facing.
	var input_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1.0

	var direction := (transform.basis * input_dir).normalized()
	var has_input := direction.length() > 0.01

	# Any movement (or leaving the ground) breaks a dance emote.
	if _dancing and (has_input or not is_on_floor()):
		_cancel_dance()

	if _rolling:
		# Committed roll: coast forward and taper off; ignore steering input.
		velocity.x = move_toward(velocity.x, 0.0, roll_slide_decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, roll_slide_decel * delta)
	else:
		# Where we WANT the horizontal velocity to be this frame (faster sprinting).
		var current_speed := sprint_speed if _sprinting else speed
		var target_x := direction.x * current_speed
		var target_z := direction.z * current_speed
		# On the ground we snap; in the air we ease so momentum carries the arc.
		var rate: float
		if is_on_floor():
			rate = ground_accel if has_input else ground_decel
		else:
			rate = air_accel if has_input else air_decel
		velocity.x = move_toward(velocity.x, target_x, rate * delta)
		velocity.z = move_toward(velocity.z, target_z, rate * delta)

	move_and_slide()
	_update_animation()

	# Footsteps while actually moving on the ground.
	if is_on_floor():
		var step_speed := Vector2(velocity.x, velocity.z).length()
		if step_speed > 1.5:
			_step_timer -= delta
			if _step_timer <= 0.0:
				Sfx.footstep()
				_step_timer = clampf(4.0 / step_speed, 0.22, 0.45)
		else:
			_step_timer = 0.0
	else:
		_step_timer = 0.0

	# Sink into the water (or fall off the world) → lose a life, respawn.
	if global_position.y < -2.0:
		_handle_death()

	_update_camera(delta)

func _update_camera(delta: float) -> void:
	if camera == null:
		return
	# Blend toward the zoomed-in conversation framing during dialogue/finale.
	var cine := Dialogue.active or Game.cinematic
	_cine_blend = move_toward(_cine_blend, 1.0 if cine else 0.0, delta / 0.35)
	var use_dist := lerpf(cam_distance, cam_dialogue_distance, _cine_blend)
	var use_height := lerpf(cam_height, cam_dialogue_height, _cine_blend)
	# Ideal camera spot: up + behind the player, in pivot space.
	var offset := Vector3(0.0, use_height, use_dist)
	var from := camera_pivot.global_position
	var ideal := camera_pivot.to_global(offset)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, ideal)
	q.collision_mask = 1          # terrain, trees/rocks, platforms (not enemies)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var target := 1.0
	if not hit.is_empty():
		var d: float = (hit.position - from).length()
		target = clampf(d / offset.length() - 0.06, 0.2, 1.0)  # sit just in front of the wall
	# Snap in instantly so we never clip; ease back out smoothly.
	if target < _cam_frac:
		_cam_frac = target
	else:
		_cam_frac = lerpf(_cam_frac, target, 1.0 - pow(0.02, delta))
	camera.position = offset * _cam_frac
