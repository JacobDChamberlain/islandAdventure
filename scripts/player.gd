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
var _cam_frac: float = 1.0   # 0..1 of the ideal distance, smoothed

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

# --- Visual model (the imported Meshy hero) ---
@export var model_target_height: float = 1.9    # how tall the hero should appear (world units)
@export var model_yaw_offset_deg: float = 180.0 # spin the model if it faces the wrong way
@export var model_y_offset: float = 0.0         # nudge up/down if feet sink or float

# --- Sprint (double-tap W and hold) ---
@export var sprint_speed: float = 20.0     # speed while sprinting
@export var double_tap_window: float = 0.3 # max seconds between the two W taps

# --- Animation clip names (must match the clips baked into the .glb) ---
@export var anim_idle: String = "Idle_6"
@export var anim_run: String = "Running"
@export var anim_run_fast: String = "RunFast"
@export var anim_jump: String = "Jump_with_Arms_Open"
@export var anim_sprint_jump: String = "Run_and_Jump"
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

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var model: Node3D = get_node_or_null("Model")

func _ready() -> void:
	jumps_left = max_jumps
	_spawn_point = global_position
	add_to_group("player")   # so gems and enemies can recognize us
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
	for clip in [anim_jump, anim_sprint_jump]:
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

# Called by an enemy when it hits you from the side.
func take_hit(source_pos: Vector3) -> void:
	if _invuln > 0.0:
		return   # still flashing-invincible from the last hit
	_invuln = invuln_time
	Sfx.hurt()
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
	if Game.lose_life():
		return
	global_position = _spawn_point
	velocity = Vector3.ZERO
	_invuln = invuln_time

func _input(event: InputEvent) -> void:
	# Mouse look: horizontal turns the whole body, vertical tilts only the camera.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * Settings.sensitivity
		rotate_y(-event.relative.x * sens)
		camera_pivot.rotate_x(-event.relative.y * sens)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-70), deg_to_rad(25))
	# Click to recapture the mouse (e.g. after unpausing). Esc is handled by the
	# pause menu, not here.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Jump on the moment Space is pressed (not while held), so double-jump works.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
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
	# Ideal camera spot: up + behind the player, in pivot space.
	var offset := Vector3(0.0, cam_height, cam_distance)
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
