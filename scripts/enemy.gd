extends CharacterBody3D
# A "nightmare head" enemy that HUNTS. It normally wanders and does goofy idle
# animations, but when the player comes near it chases them down and performs
# attack animations (kicks/stomps/slams) that deal damage after a short wind-up.
# Stomp its head while falling to defeat it.
#
# Collision: the body is on layer 2, the player collides only with layer 1, so
# the player passes THROUGH it; the Detector area handles stomp detection.

@export var walk_speed: float = 3.0
@export var run_speed: float = 6.5
@export var sprint_speed: float = 11.0
@export var chase_speed: float = 7.5
@export var roam_radius: float = 35.0
@export var detect_range: float = 14.0    # starts chasing within this distance
@export var lose_range: float = 24.0      # gives up beyond this
@export var attack_range: float = 2.8     # attacks within this
@export var attack_windup: float = 0.35   # telegraph delay before an attack lands
@export var gravity: float = 30.0
@export var model_height: float = 2.6
@export var model_yaw_offset_deg: float = 180.0

enum State { WANDER, PAUSE, CHASE, ATTACK }

const WALK := "Walking"
const RUN := "Running"
const SPRINT := "RunFast"
const ATTACKS: Array[String] = [
	"High_Kick", "Attack", "Angry_Ground_Stomp_2", "Backflip_Sweep_Kick", "Jump_and_Slam_Back_Down",
]
const IDLE_ACTIONS: Array[String] = [
	"Idle_6", "Big_Wave_Hello", "FunnyDancing_03", "Breakdance_1990", "360_Power_Spin_Jump",
	"Jump_Over_Obstacle_1", "Jump_with_Arms_and_Legs_Open", "jump_push_up", "Confident_Walk",
	"Axe_Breathe_and_Look_Around",
]

var _state: int = State.WANDER
var _timer: float = 0.0
var _heading: Vector3 = Vector3.FORWARD
var _cur_speed: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _atk_timer: float = 0.0
var _atk_dealt: bool = false
var _anim: AnimationPlayer
var _model: Node3D
var _island: Node = null
var _player: Node3D = null
var _rng := RandomNumberGenerator.new()
var _steps_player: AudioStreamPlayer3D
var _voice_player: AudioStreamPlayer3D
var _step_timer: float = 0.0
var _base_pitch: float = 1.0

func _ready() -> void:
	_rng.randomize()
	$Detector.body_entered.connect(_on_detector_body_entered)
	await get_tree().process_frame
	_island = get_tree().get_first_node_in_group("island")
	if _island and _island.has_method("height_at"):
		var half := model_height * 0.5 * global_transform.basis.get_scale().y
		global_position.y = _island.height_at(global_position.x, global_position.z) + half
	_home = global_position
	_setup_model()
	_setup_audio()
	_enter_wander()

func _setup_audio() -> void:
	var sc: float = global_transform.basis.get_scale().y
	_base_pitch = clampf(1.0 / sqrt(sc), 0.45, 1.0)   # bigger head = deeper voice/steps
	_steps_player = AudioStreamPlayer3D.new()
	_steps_player.unit_size = 9.0
	_steps_player.max_distance = 45.0
	_steps_player.volume_db = 4.0 + (sc - 1.0) * 3.0
	add_child(_steps_player)
	_voice_player = AudioStreamPlayer3D.new()
	_voice_player.unit_size = 9.0
	_voice_player.max_distance = 50.0
	_voice_player.volume_db = -4.0 + (sc - 1.0) * 3.0
	add_child(_voice_player)

func _play3d(p: AudioStreamPlayer3D, stream: AudioStream, pitch_var: float) -> void:
	if p == null or stream == null:
		return
	p.stream = stream
	p.pitch_scale = _base_pitch * (1.0 + _rng.randf_range(-pitch_var, pitch_var))
	p.play()

# --- Animation / state --------------------------------------------------------

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

func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player

func _on_anim_finished(_name: String) -> void:
	# Idle actions and attacks are one-shots → decide what to do next.
	if _state == State.PAUSE or _state == State.ATTACK:
		_reevaluate()

func _reevaluate() -> void:
	var p := _get_player()
	if p:
		var d := global_position.distance_to(p.global_position)
		if d <= attack_range:
			_enter_attack()
			return
		elif d <= detect_range:
			_enter_chase()
			return
	_enter_wander()

func _enter_wander() -> void:
	_state = State.WANDER
	var roll := _rng.randf()
	var clip: String
	if roll < 0.65:
		_cur_speed = walk_speed; clip = WALK; _timer = _rng.randf_range(2.5, 5.0)
	elif roll < 0.9:
		_cur_speed = run_speed; clip = RUN; _timer = _rng.randf_range(1.5, 3.0)
	else:
		_cur_speed = sprint_speed; clip = SPRINT; _timer = _rng.randf_range(1.0, 2.0)
	_heading = Vector3(cos(_rng.randf() * TAU), 0.0, sin(_rng.randf() * TAU))
	_play(clip)

func _enter_pause() -> void:
	_state = State.PAUSE
	_play(IDLE_ACTIONS[_rng.randi() % IDLE_ACTIONS.size()])
	_play3d(_voice_player, Sfx.random_weird(), 0.18)   # a weird noise with the goof

func _enter_chase() -> void:
	_state = State.CHASE
	_play(RUN)

func _enter_attack() -> void:
	_state = State.ATTACK
	_atk_timer = attack_windup
	_atk_dealt = false
	_play(ATTACKS[_rng.randi() % ATTACKS.size()])
	if _rng.randf() < 0.6:
		_play3d(_voice_player, Sfx.random_weird(), 0.18)

func _play(clip: String) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.play(clip, 0.15)

# --- Movement / behavior ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var p := _get_player()
	var dist := INF
	if p:
		dist = global_position.distance_to(p.global_position)

	match _state:
		State.WANDER:
			if p and dist <= detect_range:
				_enter_chase()
			else:
				_wander_move(delta)
		State.PAUSE:
			if p and dist <= detect_range:
				_enter_chase()
			else:
				_brake(delta)
		State.CHASE:
			if p == null or dist > lose_range:
				_enter_wander()
			elif dist <= attack_range:
				_enter_attack()
			else:
				_chase_move(p, delta)
		State.ATTACK:
			_brake(delta)
			if p:
				_face(p.global_position - global_position, delta)
			# Land the hit partway through the swing, if the player is still close.
			if not _atk_dealt:
				_atk_timer -= delta
				if _atk_timer <= 0.0:
					_atk_dealt = true
					if p and global_position.distance_to(p.global_position) <= attack_range * 1.4 and p.has_method("take_hit"):
						p.take_hit(global_position)

	move_and_slide()

	# Positional footsteps while actually moving on the ground.
	if is_on_floor():
		var sh := Vector2(velocity.x, velocity.z).length()
		if sh > 1.5:
			_step_timer -= delta
			if _step_timer <= 0.0:
				_play3d(_steps_player, Sfx.random_step(), 0.2)
				_step_timer = clampf(4.0 / sh, 0.22, 0.5)
		else:
			_step_timer = 0.0
	else:
		_step_timer = 0.0

func _wander_move(delta: float) -> void:
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

func _chase_move(p: Node3D, delta: float) -> void:
	var dir := p.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed
	_face(dir, delta)

func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)

func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	var target := atan2(dir.x, dir.z) + deg_to_rad(model_yaw_offset_deg)
	_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - pow(0.001, delta))

# --- Combat -------------------------------------------------------------------

func _on_detector_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	# Stomp = player above the enemy's upper half AND falling. (Scales with size,
	# so the giant has to be hit near the top of its head.)
	var world_half := model_height * 0.5 * global_transform.basis.get_scale().y
	var from_above: bool = body.global_position.y > global_position.y + world_half * 0.5
	var falling: bool = body.velocity.y < 0.0
	if from_above and falling:
		body.bounce()
		_die()

func _die() -> void:
	var sc: float = global_transform.basis.get_scale().y
	Fx.poof(global_position, Color(0.55, 0.6, 0.35), int(min(sc, 4.0) * 8) + 12, sc)
	Sfx.stomp()
	queue_free()

# --- Model fitting ------------------------------------------------------------

func _fit_model(model: Node3D) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel := skels[0] as Skeleton3D
	var inv := model.global_transform.affine_inverse()
	var aabb := AABB()
	var first := true
	for i in skel.get_bone_count():
		var pos: Vector3 = inv * (skel.global_transform * skel.get_bone_global_pose(i)).origin
		if first:
			aabb = AABB(pos, Vector3.ZERO)
			first = false
		else:
			aabb = aabb.expand(pos)
	if first or aabb.size.y <= 0.0:
		return
	var s := model_height / aabb.size.y
	model.scale = Vector3.ONE * s
	model.position = Vector3(0.0, -(model_height * 0.5) - aabb.position.y * s, 0.0)
	model.rotation_degrees.y = model_yaw_offset_deg

func _strip_root_motion(anim: AnimationPlayer) -> void:
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
