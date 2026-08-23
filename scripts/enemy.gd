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
@export var max_hp: int = 2                    # melee hits to defeat (stomp is always instant)
@export var model_height: float = 2.6
@export var model_yaw_offset_deg: float = 180.0
@export var night_detect_mult: float = 1.7   # detect/lose range multiplier at night
@export var night_speed_mult: float = 1.25    # chase-speed multiplier at night
@export var exotic_drop_chance: float = 0.28  # chance to drop Exotic Matter when defeated
@export var coin_min: int = 3                 # coins dropped when defeated (range)
@export var coin_max: int = 7

const EXOTIC_SCENE := preload("res://scenes/exotic_matter.tscn")
const COIN_SCENE := preload("res://scenes/coin.tscn")

# Emitted when this head is stomped, so the level can respawn it after a delay.
signal died()

enum State { WANDER, PAUSE, CHASE, ATTACK, HIT }

const WALK := "Walking"
const RUN := "Running"
const SPRINT := "RunFast"
const HIT_FRONT := "Hit_Reaction"
const HIT_BACK := "Hit_in_Back_While_Running"
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
var _hp: int = 2
var _kb_timer: float = 0.0   # while >0, coast from a knockback and ignore the AI

func _ready() -> void:
	_rng.randomize()
	add_to_group("enemy")
	_hp = max_hp
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

# --- Night aggression: heads see farther, hunt longer, and run faster at night.
func _detect_range() -> float:
	return detect_range * (night_detect_mult if Game.is_night else 1.0)

func _lose_range() -> float:
	return lose_range * (night_detect_mult if Game.is_night else 1.0)

func _chase_speed() -> float:
	return chase_speed * (night_speed_mult if Game.is_night else 1.0)

func _on_anim_finished(_name: String) -> void:
	# Idle actions and attacks are one-shots → decide what to do next.
	if _state == State.PAUSE or _state == State.ATTACK or _state == State.HIT:
		_reevaluate()

func _reevaluate() -> void:
	var p := _get_player()
	if p:
		var d := global_position.distance_to(p.global_position)
		if d <= attack_range:
			_enter_attack()
			return
		elif d <= _detect_range():
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
	# Knocked back by a player attack: coast + slow, ignore the AI for a moment.
	if _kb_timer > 0.0:
		_kb_timer -= delta
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		move_and_slide()
		return

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
			if p and dist <= _detect_range():
				_enter_chase()
			else:
				_wander_move(delta)
		State.PAUSE:
			if p and dist <= _detect_range():
				_enter_chase()
			else:
				_brake(delta)
		State.CHASE:
			if p == null or dist > _lose_range():
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
		State.HIT:
			_brake(delta)

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
	var cs := _chase_speed()
	velocity.x = dir.x * cs
	velocity.z = dir.z * cs
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
	# Running into an enemy no longer flinches it — hit reactions come only from
	# the player's punches/kicks (see hit_by_player).

# Called by the player's melee attack. Takes damage + knockback; a non-lethal hit
# flinches and then makes the head retaliate (chase). Lethal hits die (drop loot).
func hit_by_player(from_pos: Vector3, knockback: float, damage: int = 1) -> void:
	if _kb_timer > 0.0 and _hp <= 0:
		return
	_hp -= damage
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() < 0.01:
		away = -_heading
	away = away.normalized()
	# Heavier heads get shoved less.
	var mass_factor: float = 1.0 / maxf(1.0, global_transform.basis.get_scale().y)
	velocity.x = away.x * knockback * mass_factor
	velocity.z = away.z * knockback * mass_factor
	velocity.y = 4.5
	_kb_timer = 0.28
	if _hp <= 0:
		_die()
	else:
		var fwd := Vector3(velocity.x, 0.0, velocity.z)
		if fwd.length() < 0.1:
			fwd = _heading
		var from_back := (from_pos - global_position).dot(fwd) < 0.0
		_enter_hit(from_back)

func _enter_hit(from_back: bool) -> void:
	_state = State.HIT
	_play(HIT_BACK if from_back else HIT_FRONT)

func _die() -> void:
	var sc: float = global_transform.basis.get_scale().y
	Fx.poof(global_position, Color(0.55, 0.6, 0.35), int(min(sc, 4.0) * 8) + 12, sc)
	Sfx.stomp()
	_drop_coins()
	_maybe_drop_exotic()
	died.emit()
	queue_free()

# Scatter a random handful of coins; bigger heads pay out a little more.
func _drop_coins() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var sc: float = global_transform.basis.get_scale().y
	var n := _rng.randi_range(coin_min, coin_max) + int((sc - 1.0) * 2.0)
	for i in n:
		var c := COIN_SCENE.instantiate()
		parent.add_child(c)
		c.global_position = global_position + Vector3.UP * 1.0

# Roll for a rare Exotic Matter drop; bigger heads are a bit likelier to yield it.
func _maybe_drop_exotic() -> void:
	var sc: float = global_transform.basis.get_scale().y
	var chance := clampf(exotic_drop_chance * (1.0 + (sc - 1.0) * 0.2), 0.0, 0.9)
	if _rng.randf() > chance:
		return
	var drop := EXOTIC_SCENE.instantiate()
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(drop)
	drop.global_position = global_position + Vector3.UP * 1.0

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
