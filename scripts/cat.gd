extends Node3D
# The shop cat. Wanders a small patrol area in front of the shop, walking and
# pausing to sit. The sitting model (clip0) and the walk clip (merged from the
# walking GLB — same rig) share one AnimationPlayer. Meshy models come in tiny +
# rotated, so scale/yaw are tunable. Stage 2 (hopping on/off the counter) later.

const WALK_GLB := "res://assets/models/shopcat_walk.glb"
const SIT_CLIP := "Armature|clip0|baselayer"
const WALK_SRC := "Armature|Unreal Take|baselayer"

@export var shop_name: String = "Biscuit"       # the cat shopkeeper's name
@export var grapple_price: int = 25
@export var target_height: float = 0.35        # rendered (sitting) height in metres
@export var model_scale: float = 0.0            # 0 = auto-fit to target_height
@export var model_y_offset: float = 0.0         # nudge up/down so she sits on the ground
@export var model_yaw_offset_deg: float = 180.0
@export var walk_speed: float = 0.55
@export var patrol_radius: float = 2.5
@export var sit_time: Vector2 = Vector2(3.0, 7.0)
@export var walk_time: Vector2 = Vector2(2.0, 5.0)

var _model: Node3D
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _base_scale: float = 1.0        # scale for the sitting clip
var _walk_scale_mult: float = 1.0   # extra scale while walking (walk clip baked smaller)
var _home: Vector3
var _heading: Vector3 = Vector3.FORWARD
var _sitting: bool = true
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _island: Node
var _player_near: bool = false
var _talking: bool = false
@onready var prompt: Label3D = $Prompt

func _ready() -> void:
	_rng.randomize()
	_model = get_node_or_null("Model")
	if _model:
		for c in _model.find_children("*", "AnimationPlayer", true, false):
			_anim = c as AnimationPlayer
			break
		for c in _model.find_children("*", "Skeleton3D", true, false):
			_skel = c as Skeleton3D
			break
		_merge_walk()
		if _anim:
			for clip in [SIT_CLIP, "walk"]:
				if _anim.has_animation(clip):
					_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			_strip_root_motion(_anim)
		_fit()
	$TalkZone.body_entered.connect(_on_zone_entered)
	$TalkZone.body_exited.connect(_on_zone_exited)
	prompt.visible = false
	await get_tree().process_frame
	_island = get_tree().get_first_node_in_group("island")
	_snap()
	_home = global_position
	await _calibrate_scales()   # the two clips baked different sizes — match them
	_enter_sit()

# Meshy baked a different scale into each clip. Measure both and compute a walk
# multiplier so she stays the sitting size while moving.
func _calibrate_scales() -> void:
	if _anim == null or _skel == null:
		return
	if not (_anim.has_animation(SIT_CLIP) and _anim.has_animation("walk")):
		return
	_anim.play(SIT_CLIP)
	await get_tree().process_frame
	await get_tree().process_frame
	var hs := _skel_height()
	_anim.play("walk")
	await get_tree().process_frame
	await get_tree().process_frame
	var hw := _skel_height()
	if hw > 0.001:
		_walk_scale_mult = hs / hw

func _skel_height() -> float:
	if _skel == null:
		return 0.0
	var a := AABB()
	var first := true
	for i in _skel.get_bone_count():
		var p: Vector3 = (_skel.global_transform * _skel.get_bone_global_pose(i)).origin
		if first:
			a = AABB(p, Vector3.ZERO); first = false
		else:
			a = a.expand(p)
	return a.size.y

# Copy the walk animation off the walking GLB (identical rig) into our player.
func _merge_walk() -> void:
	if _anim == null:
		return
	var scene := load(WALK_GLB) as PackedScene
	if scene == null:
		return
	var inst := scene.instantiate()
	var wap: AnimationPlayer = null
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		wap = c as AnimationPlayer
		break
	if wap and wap.has_animation(WALK_SRC):
		var lib := _anim.get_animation_library("")
		if lib:
			lib.add_animation("walk", wap.get_animation(WALK_SRC).duplicate())
	inst.free()

func _fit() -> void:
	if _model == null:
		return
	var s: float = model_scale
	if s <= 0.0:
		var aabb := _skeleton_aabb(_model)
		s = target_height / maxf(aabb.size.y, 0.001)
	_base_scale = s
	_model.scale = Vector3.ONE * s
	_model.position = Vector3(0.0, model_y_offset, 0.0)   # ground-snap seats her; nudge here if needed
	_model.rotation_degrees.y = model_yaw_offset_deg

func _skeleton_aabb(model: Node3D) -> AABB:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		var inv := model.global_transform.affine_inverse()
		var aabb := AABB()
		var first := true
		for i in skel.get_bone_count():
			var p: Vector3 = inv * (skel.global_transform * skel.get_bone_global_pose(i)).origin
			if first:
				aabb = AABB(p, Vector3.ZERO); first = false
			else:
				aabb = aabb.expand(p)
		if not first:
			return aabb
	return AABB(Vector3.ZERO, Vector3.ONE)

func _strip_root_motion(a: AnimationPlayer) -> void:
	for clip_name in a.get_animation_list():
		var clip := a.get_animation(clip_name)
		for ti in clip.get_track_count():
			if clip.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			var kc := clip.track_get_key_count(ti)
			if kc == 0:
				continue
			var base: Vector3 = clip.track_get_key_value(ti, 0)
			for k in range(1, kc):
				clip.track_set_key_value(ti, k, base)

func _snap() -> void:
	if _island and _island.has_method("height_at"):
		global_position.y = _island.height_at(global_position.x, global_position.z)

func _enter_sit() -> void:
	_sitting = true
	_timer = _rng.randf_range(sit_time.x, sit_time.y)
	if _model:
		_model.scale = Vector3.ONE * _base_scale
	if _anim and _anim.has_animation(SIT_CLIP):
		_anim.play(SIT_CLIP)

func _enter_walk() -> void:
	_sitting = false
	_timer = _rng.randf_range(walk_time.x, walk_time.y)
	_heading = Vector3(cos(_rng.randf() * TAU), 0.0, sin(_rng.randf() * TAU))
	if _model:
		_model.scale = Vector3.ONE * _base_scale * _walk_scale_mult   # keep the sitting size
	if _anim and _anim.has_animation("walk"):
		_anim.play("walk")

func _process(delta: float) -> void:
	if _talking:
		return   # sit still while the shop dialogue is up
	_timer -= delta
	if _sitting:
		if _timer <= 0.0:
			_enter_walk()
		return
	# Steer back toward home if we drift out of the patrol area.
	if global_position.distance_to(_home) > patrol_radius:
		var back := _home - global_position
		back.y = 0.0
		if back.length() > 0.01:
			_heading = back.normalized()
	global_position += _heading * walk_speed * delta
	_snap()
	_face(_heading, delta)
	if _timer <= 0.0:
		_enter_sit()

func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	var target := atan2(dir.x, dir.z) + deg_to_rad(model_yaw_offset_deg)
	_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - pow(0.001, delta))

# --- Shopkeeper interaction ---------------------------------------------------

func _on_zone_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = true
		if not Dialogue.active:
			prompt.visible = true

func _on_zone_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = false
		prompt.visible = false

func _input(event: InputEvent) -> void:
	if not _player_near or Dialogue.active or _talking:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		_talk()

func _talk() -> void:
	prompt.visible = false
	_talking = true
	_enter_sit()          # she plops down to "chat"
	Game.cinematic = true # freeze the player + zoom the camera in (frames the cat)
	_face_conversation()
	if Game.has_grapple:
		Dialogue.finished.connect(_end_talk, CONNECT_ONE_SHOT)
		Dialogue.start(shop_name, ["Mrrp. You've already got the hook. *flicks tail*"])
	elif Game.coins < grapple_price:
		Dialogue.finished.connect(_end_talk, CONNECT_ONE_SHOT)
		Dialogue.start(shop_name, [
			"Meow. (Grappling Hook: %d coins.)" % grapple_price,
			"You've got %d. Go bonk some heads, human." % Game.coins,
		])
	else:
		Dialogue.confirmed.connect(_on_confirmed, CONNECT_ONE_SHOT)
		Dialogue.ask(shop_name, [
			"Mrrow? *nudges a Grappling Hook across the counter*",
			"%d coins and it's yours. We got a deal?" % grapple_price,
		])

func _on_confirmed(accepted: bool) -> void:
	if accepted and not Game.has_grapple and Game.spend_coins(grapple_price):
		Game.has_grapple = true
		Sfx.exotic()
		Dialogue.finished.connect(_end_talk, CONNECT_ONE_SHOT)
		Dialogue.start(shop_name, ["Purrrr. Tap Q (or middle-mouse) to swing. Don't scratch the walls."])
	else:
		_end_talk()

func _end_talk() -> void:
	Game.cinematic = false
	_talking = false
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		var pcam := p.get_node_or_null("CameraPivot/Camera3D") as Camera3D
		if pcam:
			pcam.current = true   # hand the view back to the player
	_timer = _rng.randf_range(sit_time.x, sit_time.y)   # sit a beat before wandering off
	if _player_near:
		prompt.visible = true

# Turn the player to face the cat and the cat to face the player, so the zoomed
# conversation camera frames her.
func _face_conversation() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var look := Vector3(global_position.x, p.global_position.y, global_position.z)
	if look.distance_to(p.global_position) > 0.05:
		p.look_at(look, Vector3.UP)
	var dir := p.global_position - global_position
	dir.y = 0.0
	_face(dir, 1.0)
	_focus_camera(p)

# A dedicated low camera on the player's side of the cat, looking slightly UP at
# her for a close-up while she talks.
func _focus_camera(p: Node3D) -> void:
	var cam := get_node_or_null("CatCam") as Camera3D
	if cam == null:
		return
	var to_player := p.global_position - global_position
	to_player.y = 0.0
	to_player = to_player.normalized() if to_player.length() > 0.01 else Vector3.FORWARD
	cam.global_position = global_position + to_player * 1.1 + Vector3.UP * 0.2   # near the floor, close
	cam.look_at(global_position + Vector3.UP * 0.55, Vector3.UP)                 # look up at her
	cam.current = true
