extends CharacterBody3D
# A wandering "nightmare head" enemy. It roams the island (mostly walking, but
# sometimes decides to run or sprint), pauses to perform a random goofy animation,
# and reacts when the player bumps into it (a front or a from-behind hit). Stomp
# its head while falling to defeat it.
#
# Collision: the body is on layer 2 and the player collides only with layer 1, so
# the player passes THROUGH it; the Detector area does all the contact detection,
# which lets us read the player's real falling speed to tell a stomp from a bump.

@export var walk_speed: float = 3.0
@export var run_speed: float = 6.5
@export var sprint_speed: float = 11.0
@export var roam_radius: float = 35.0        # how far it wanders from where it spawned
@export var gravity: float = 30.0
@export var model_height: float = 2.6        # how tall the head-bust appears
@export var model_yaw_offset_deg: float = 180.0  # flip if the head faces backwards

enum State { WANDER, PAUSE, HIT }

const WALK := "Walking"
const RUN := "Running"
const SPRINT := "RunFast"
const HIT_FRONT := "Hit_Reaction"
const HIT_BACK := "Hit_in_Back_While_Running"
# Everything that should only play while it's standing still.
const IDLE_ACTIONS: Array[String] = [
	"Idle_6", "Big_Wave_Hello", "FunnyDancing_03", "Breakdance_1990", "High_Kick",
	"Attack", "Axe_Breathe_and_Look_Around", "360_Power_Spin_Jump", "Jump_Over_Obstacle_1",
	"Jump_and_Slam_Back_Down", "Jump_with_Arms_and_Legs_Open", "jump_push_up",
	"Angry_Ground_Stomp_2", "Backflip_Sweep_Kick", "Confident_Walk",
]

var _state: int = State.WANDER
var _timer: float = 0.0
var _heading: Vector3 = Vector3.FORWARD
var _cur_speed: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _anim: AnimationPlayer
var _model: Node3D
var _island: Node = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	$Detector.body_entered.connect(_on_detector_body_entered)
	await get_tree().process_frame
	_island = get_tree().get_first_node_in_group("island")
	if _island and _island.has_method("height_at"):
		# Offset by the world-space half-height (accounts for a scaled-up giant).
		var half := model_height * 0.5 * global_transform.basis.get_scale().y
		global_position.y = _island.height_at(global_position.x, global_position.z) + half
	_home = global_position
	_setup_model()
	_enter_wander()

# --- Animation state machine -------------------------------------------------

func _setup_model() -> void:
	_model = get_node_or_null("Model")
	if _model == null:
		return
	_fit_model(_model)
	_anim = _model.get_node_or_null("AnimationPlayer")
	if _anim == null:
		return
	for clip_name in _anim.get_animation_list():
		var loops := clip_name == WALK or clip_name == RUN or clip_name == SPRINT
		_anim.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	_strip_root_motion(_anim)
	_anim.animation_finished.connect(_on_anim_finished)

func _on_anim_finished(_name: String) -> void:
	# One-shot pauses and hit reactions return to wandering when they end.
	if _state == State.PAUSE or _state == State.HIT:
		_enter_wander()

func _enter_wander() -> void:
	_state = State.WANDER
	var roll := _rng.randf()
	var clip: String
	if roll < 0.65:      # usually just strolls
		_cur_speed = walk_speed
		clip = WALK
		_timer = _rng.randf_range(2.5, 5.0)
	elif roll < 0.9:     # sometimes decides to run
		_cur_speed = run_speed
		clip = RUN
		_timer = _rng.randf_range(1.5, 3.0)
	else:                # occasionally sprints, for whatever reason
		_cur_speed = sprint_speed
		clip = SPRINT
		_timer = _rng.randf_range(1.0, 2.0)
	var ang := _rng.randf() * TAU
	_heading = Vector3(cos(ang), 0.0, sin(ang))
	_play(clip)

func _enter_pause() -> void:
	_state = State.PAUSE
	_play(IDLE_ACTIONS[_rng.randi() % IDLE_ACTIONS.size()])

func _enter_hit(from_back: bool) -> void:
	_state = State.HIT
	_play(HIT_BACK if from_back else HIT_FRONT)

func _play(clip: String) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.play(clip, 0.15)

# --- Movement ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _state == State.WANDER:
		# Steer back toward home at the shoreline or when it strays too far.
		var ahead := global_position + _heading * 3.0
		var too_far := global_position.distance_to(_home) > roam_radius
		var into_water: bool = _island != null and _island.height_at(ahead.x, ahead.z) < 1.5
		if too_far or into_water:
			var back := _home - global_position
			back.y = 0.0
			if back.length() > 0.01:
				_heading = back.normalized().rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
		velocity.x = _heading.x * _cur_speed
		velocity.z = _heading.z * _cur_speed
		_face(_heading, delta)
		_timer -= delta
		if _timer <= 0.0:
			_enter_pause()
	else:
		# Paused or reacting → stand still.
		velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)

	move_and_slide()

func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	var target := atan2(dir.x, dir.z) + deg_to_rad(model_yaw_offset_deg)
	_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - pow(0.001, delta))

# --- Combat ------------------------------------------------------------------

func _on_detector_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var from_above: bool = body.global_position.y > global_position.y + 0.5
	var falling: bool = body.velocity.y < 0.0
	if from_above and falling:
		body.bounce()
		_die()
	else:
		# Bumped: the player takes damage AND the head flinches, front or back.
		var to_player := body.global_position - global_position
		var from_back := to_player.dot(_heading) < 0.0
		body.take_hit(global_position)
		_enter_hit(from_back)

func _die() -> void:
	queue_free()

# --- Model fitting ------------------------------------------------------------

func _fit_model(model: Node3D) -> void:
	# Scale the rigged head to model_height using the skeleton's true extent
	# (its mesh AABB ignores the ~100x scale Meshy bakes into the rig).
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
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
	if first or aabb.size.y <= 0.0:
		return
	var s := model_height / aabb.size.y
	model.scale = Vector3.ONE * s
	# Plant the feet at the bottom of a model_height-tall collision capsule.
	model.position = Vector3(0.0, -(model_height * 0.5) - aabb.position.y * s, 0.0)
	model.rotation_degrees.y = model_yaw_offset_deg

func _strip_root_motion(anim: AnimationPlayer) -> void:
	# Freeze bone POSITION tracks so animations play in place (no baked travel).
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
