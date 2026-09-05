extends Node3D
# The shop cat. Wanders a small patrol area in front of the shop, walking and
# pausing to sit. The sitting model (clip0) and the walk clip (merged from the
# walking GLB — same rig) share one AnimationPlayer. Meshy models come in tiny +
# rotated, so scale/yaw are tunable. Stage 2 (hopping on/off the counter) later.

const WALK_GLB := "res://assets/models/shopcat_walk.glb"
const SIT_CLIP := "Armature|clip0|baselayer"
const WALK_SRC := "Armature|Unreal Take|baselayer"

@export var shop_name: String = "Biscuit"       # the cat shopkeeper's name
@export_multiline var greetings: PackedStringArray = ["Mow.", "Mow?"]
# Rare comeback. Gated on the quest being underway, since it answers something
# Spencer said — before that, you haven't met him and the line makes no sense.
@export_multiline var rare_greeting: String = "Mrow.\nYou spoke with Spencer? That dirty human lies. I owe him nothing."
@export var rare_greeting_chance: float = 0.08
@export var grapple_price: int = 25
@export var gun_price: int = 40
@export var ammo_price: int = 10
@export var ammo_per_purchase: int = 60
@export var refill_price: int = 30          # top the blaster all the way up
@export var reset_weapon_price: int = 5     # "standard barrel" — undo an upgrade
@export var target_height: float = 0.35        # rendered (sitting) height in metres
@export var model_scale: float = 0.0            # 0 = auto-fit to target_height
@export var model_y_offset: float = 0.0         # nudge up/down so she sits on the ground
@export var model_yaw_offset_deg: float = 180.0
@export var walk_speed: float = 0.55
@export var patrol_radius: float = 2.5
@export var sit_time: Vector2 = Vector2(3.0, 7.0)
@export var walk_time: Vector2 = Vector2(2.0, 5.0)
# --- "Take Biscuit for a walk": she tags along and fetches things for you ---
@export var follow_speed: float = 9.0        # must out-run the hero's 13 in short bursts
@export var follow_distance: float = 2.0     # how close she trots behind you
@export var follow_teleport_dist: float = 45.0  # if you truly lose her, she catches up
@export var fetch_radius: float = 7.0        # she hoovers up pickups within this
@export var fetch_artifacts: bool = false    # artifacts are YOUR job by default
@export var fetch_reach: float = 1.1         # she must actually reach an item to take it
@export var fetch_speed: float = 7.0         # trot speed when going for a pickup
@export var fetch_give_up: float = 4.0       # seconds of no progress before she abandons an item
@export var pad_trigger_radius: float = 2.2  # how close she must be to a launch pad
@export var cat_gravity: float = 30.0
@export var pad_play_radius: float = 9.0     # stay near a pad and she'll keep bouncing with you
@export var obstacle_look_ahead: float = 4.5 # how far ahead she checks for a wall
@export var steer_commit: float = 0.7       # seconds she commits to a detour before re-thinking
@export var stuck_time: float = 2.5         # no progress for this long = she finds her own way
@export var roof_hop_height: float = 4.0     # if you're this far above her...
@export var roof_hop_reach: float = 9.0      # ...and this close, she hops up to you

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
var _menu: CanvasLayer = null   # the menu window (scripts/shop_menu.gd)
var _following: bool = false    # out for a walk with the player
var _fetch_target: Node3D = null
var _fetch_t: float = 0.0        # time spent on the current target
var _fetch_best: float = 999.0   # closest she has got to it
var _unreachable: Dictionary = {}  # instance ids she has given up on
var _air_vel: Vector3 = Vector3.ZERO
var _airborne: bool = false
var _pad_cd: float = 0.0
var _pad_last: Node = null   # the pad she just used; can't re-fire until she leaves it
var _steer_dir: Vector3 = Vector3.ZERO
var _steer_hold: float = 0.0
var _stuck_t: float = 0.0
var _best_dist: float = 999.0
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
	add_to_group("cat")   # so the car can compare who owns the E key
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
	global_position.y = _ground_y(global_position.x, global_position.z)

# Height she should stand at. In the city that includes ROOFTOPS: if the person
# she's following is up on one, she stands on it too, so a grapple onto a roof
# doesn't leave her stuck in the street below.
# Cast down for the real surface under her — that picks up rooftops, platforms
# and terrain alike. Falls back to the ground's height_at if the ray misses.
func _ground_y(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var top := Vector3(x, global_position.y + 3.0, z)
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 400.0)
	q.collision_mask = 1
	q.collide_with_areas = false
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player is CollisionObject3D:
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit.position.y
	if _island != null and _island.has_method("height_at"):
		return _island.height_at(x, z)
	return global_position.y

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
	_update_prompt()
	if _talking:
		return   # sit still while the menu/dialogue is up
	if _pad_cd > 0.0:
		_pad_cd -= delta
	if _airborne:
		_air_step(delta)
		return
	if _following:
		_check_launch_pads()
		_follow_step(delta)
		return
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

# Launch pads fling her too — she's a Node3D, so she can't trigger the pad's
# Area3D herself; she watches for pads instead. Works whether or not YOU jump on
# it: wait beside one and she'll trot over it and go flying.
func _check_launch_pads() -> void:
	# A pad throws her straight up, so she lands back on it — without this she
	# pogos on the spot for ever. She has to actually step off a pad before it
	# can fling her again.
	if _pad_last != null:
		if not is_instance_valid(_pad_last):
			_pad_last = null
		elif _flat_dist(_pad_last.global_position) > pad_trigger_radius * 1.8:
			_pad_last = null
		elif _player_near_pad(_pad_last):
			_pad_last = null   # you're playing on the pad too — let her keep bouncing
	if _pad_cd > 0.0:
		return
	for pad in get_tree().get_nodes_in_group("launch_pad"):
		if not is_instance_valid(pad) or pad == _pad_last:
			continue
		if _flat_dist(pad.global_position) <= pad_trigger_radius \
				and absf(pad.global_position.y - global_position.y) < 3.0:
			_pad_last = pad
			launch(pad.strength if "strength" in pad else 20.0)
			return

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

# Are YOU hanging around this pad? If so she's allowed to bounce over and over;
# the "step off before it re-fires" rule only exists to stop her pogoing alone
# for ever after you've wandered off.
func _player_near_pad(pad: Node) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(pad):
		return false
	var p: Vector3 = pad.global_position
	return Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() <= pad_play_radius

func launch(strength: float) -> void:
	_air_vel.y = strength
	# Carry her forward as she goes up, so it reads as a leap towards you rather
	# than a pogo stick — and so she lands somewhere new.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and not (_pad_last != null and _player_near_pad(_pad_last)):
		var to := player.global_position - global_position
		to.y = 0.0
		if to.length() > 0.5:
			var fwd := to.normalized() * minf(follow_speed, to.length() * 0.6)
			_air_vel.x = fwd.x
			_air_vel.z = fwd.z
	_airborne = true
	_pad_cd = 1.5
	Sfx.jump()
	if _anim and _anim.has_animation("walk"):
		_anim.play("walk")

# Simple ballistic arc — she has no physics body, so we integrate her ourselves
# (same approach as the coin/Exotic Matter drops).
func _air_step(delta: float) -> void:
	_air_vel.y -= cat_gravity * delta
	global_position += _air_vel * delta
	var floor_y := _ground_y(global_position.x, global_position.z)
	if global_position.y <= floor_y and _air_vel.y <= 0.0:
		global_position.y = floor_y
		_air_vel = Vector3.ZERO
		_airborne = false
		if _following:
			_enter_walk()
		else:
			_enter_sit()

# Trot after the player — or detour to a pickup and actually walk onto it.
func _follow_step(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# Fetching takes priority, as long as it doesn't strand her miles behind you.
	_pick_fetch_target(player)
	if _fetch_target != null:
		var fto := _fetch_target.global_position - global_position
		fto.y = 0.0
		if fto.length() <= fetch_reach:
			if _fetch_target.has_method("collect"):
				_fetch_target.collect()
			_clear_fetch()
		else:
			# Give up on anything she can't actually get to — a coin sealed in a
			# building, up on a roof, over a cliff. Without this she walks at it
			# for ever. (The stuck rescue below never ran here: this branch
			# returns before it.)
			_fetch_t += delta
			if fto.length() < _fetch_best - 0.3:
				_fetch_best = fto.length()
				_fetch_t = 0.0
			if _fetch_t > fetch_give_up:
				_unreachable[_fetch_target.get_instance_id()] = true
				_clear_fetch()
				return
			if _sitting:
				_enter_walk()
			var fdir := _steer_around(fto.normalized(), delta)
			global_position += fdir * fetch_speed * delta
			_snap()
			_face(fdir, delta)
			return
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	# If the hero has genuinely outrun her (a launch pad, the car), catch up.
	if dist > follow_teleport_dist:
		global_position = player.global_position - to.normalized() * follow_distance
		_snap()
		return
	if dist <= follow_distance:
		if not _sitting:
			_enter_sit()          # at heel: sit and wait
		_face(to, delta)
		_stuck_t = 0.0
		_best_dist = 999.0
		return
	# Wall-following is only LOCAL avoidance — a long building is a dead end it
	# can't reason its way out of. If she stops making progress, she "finds her
	# own way round" and reappears at your heel, the way pet companions in most
	# open-world games do rather than pathfinding a procedural city.
	if dist < _best_dist - 0.5:
		_best_dist = dist
		_stuck_t = 0.0
	else:
		_stuck_t += delta
		if _stuck_t > stuck_time:
			global_position = player.global_position - (to / maxf(dist, 0.001)) * follow_distance
			_snap()
			_stuck_t = 0.0
			_best_dist = 999.0
			return
	if _sitting:
		_enter_walk()
	# You're on a roof / ledge she can't walk up to, and she's right below: hop up
	# rather than circling the building for ever.
	if player.global_position.y - global_position.y > roof_hop_height and dist < roof_hop_reach:
		global_position = Vector3(player.global_position.x, player.global_position.y, player.global_position.z) \
			- (to / maxf(dist, 0.001)) * follow_distance
		_snap()
		return
	var dir := _steer_around(to / maxf(dist, 0.001), delta)
	global_position += dir * follow_speed * delta
	_snap()
	_face(dir, delta)

# She has no collision body (she's a plain Node3D moved by hand), so walls are
# invisible to her unless we ask the physics world directly. NOTE: city.gd's
# building_top_at() is per-BLOCK — it reports a roof height for the whole block,
# pavement included — so it can't be used as a wall test. A real raycast against
# the world layer can.
func _blocked_ahead(from: Vector3, dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var a := from + Vector3.UP * 0.4
	var q := PhysicsRayQueryParameters3D.create(a, a + dir * obstacle_look_ahead)
	q.collision_mask = 1
	q.collide_with_areas = false
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player is CollisionObject3D:
		q.exclude = [player.get_rid()]   # you are not a wall
	return not space.intersect_ray(q).is_empty()

# Commit to a detour for `steer_commit` seconds once one is chosen. Re-picking
# every frame makes her jitter along a wall and never get round the corner.
func _steer_around(dir: Vector3, delta: float) -> Vector3:
	if _steer_hold > 0.0:
		_steer_hold -= delta
		if not _blocked_ahead(global_position, _steer_dir):
			return _steer_dir
		_steer_hold = 0.0
	if not _blocked_ahead(global_position, dir):
		return dir
	for deg in [35.0, -35.0, 70.0, -70.0, 100.0, -100.0, 135.0, -135.0]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(deg))
		if not _blocked_ahead(global_position, d):
			_steer_dir = d
			_steer_hold = steer_commit
			return d
	return dir      # boxed in — keep going; the catch-up teleport will rescue her

# Choose the nearest thing worth walking to. She keeps the same target until she
# reaches it (or it vanishes), so she doesn't dither between two coins.
func _clear_fetch() -> void:
	_fetch_target = null
	_fetch_t = 0.0
	_fetch_best = 999.0

func _pick_fetch_target(player: Node3D) -> void:
	if _fetch_target != null and is_instance_valid(_fetch_target):
		# Give up if chasing it would leave the player behind.
		if _fetch_target.global_position.distance_to(player.global_position) > fetch_radius * 2.5:
			_clear_fetch()
		else:
			return
	else:
		_clear_fetch()
	var groups := ["coin", "exotic", "ammo"]
	if fetch_artifacts:
		groups.append("artifact")
	var best := fetch_radius
	for g in groups:
		for item in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(item) or not item.has_method("collect"):
				continue
			if _unreachable.has(item.get_instance_id()):
				continue
			var d: float = item.global_position.distance_to(global_position)
			if d < best:
				best = d
				_fetch_target = item
	_fetch_t = 0.0
	_fetch_best = 999.0

func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	var target := atan2(dir.x, dir.z) + deg_to_rad(model_yaw_offset_deg)
	_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - pow(0.001, delta))

# --- Shopkeeper interaction ---------------------------------------------------

# Only the nearest interactable advertises itself, so standing by the car doesn't
# show two "Press E" labels for a key that can only do one of them.
func _update_prompt() -> void:
	if prompt == null:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	prompt.visible = _player_near and not _talking and not Dialogue.active \
		and p != null and _wins_interact(p)

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
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player != null and not _wins_interact(player):
			return          # the car (or an NPC) is closer — let them have E
		_talk()
		get_viewport().set_input_as_handled()

# Nearest interactable wins the E key, so a cat at your heel can't block the car.
func _wins_interact(player: Node3D) -> bool:
	var mine := global_position.distance_to(player.global_position)
	for g in ["vehicle", "cat", "npc"]:
		for other in get_tree().get_nodes_in_group(g):
			if other == self or not is_instance_valid(other) or not (other is Node3D):
				continue
			if other.global_position.distance_to(player.global_position) < mine - 0.01:
				return false
	return true

func _talk() -> void:
	prompt.visible = false
	_talking = true
	_enter_sit()          # she plops down to "chat"
	Game.cinematic = true # freeze the player + zoom the camera in (frames the cat)
	_face_conversation()
	# Greeting first (zoomed in, typewriter), then the choice menu.
	Dialogue.finished.connect(_open_main_menu, CONNECT_ONE_SHOT)
	Dialogue.start(shop_name, [_greeting()])

func _greeting() -> String:
	if rare_greeting != "" and Game.quest_active and _rng.randf() < rare_greeting_chance:
		return rare_greeting
	if greetings.is_empty():
		return "Mow."
	return greetings[_rng.randi() % greetings.size()]

# --- Main menu ----------------------------------------------------------------

func _ensure_menu() -> void:
	if _menu != null:
		return
	_menu = load("res://scripts/shop_menu.gd").new()
	add_child(_menu)
	_menu.bought.connect(_on_chosen)
	_menu.closed.connect(_end_talk)

func _open_main_menu() -> void:
	_ensure_menu()
	_menu.open(_main_items(), "What'll it be?", shop_name.to_upper())

func _main_items() -> Array:
	var walk_row := {
		"id": "walk", "name": "Take Biscuit for a walk",
		"note": "She follows you and picks up coins, Exotic Matter and ammo.",
		"enabled": true,
	}
	if _following:
		walk_row = {
			"id": "stop_walk", "name": "End the walk",
			"note": "She stays put here and goes back to her pottering.",
			"enabled": true,
		}
	return [
		{"id": "shop", "name": "Enter shop", "note": "Hook, blaster, ammo, upgrades."},
		walk_row,
		{"id": "leave", "name": "Leave", "note": "Back to it."},
	]

# --- Shop window --------------------------------------------------------------

func _open_shop() -> void:
	_ensure_menu()
	_menu.show_items(_stock(), "*nudges the tray forward*", "BISCUIT'S SHOP")

# What's on the counter right now. Owned things stay listed but greyed out, so
# the shelf doesn't rearrange itself under the player's cursor between buys.
func _stock() -> Array:
	var items: Array = []
	items.append({
		"id": "grapple", "name": "Grappling Hook", "price": grapple_price,
		"note": "Q or middle-mouse to swing up onto roofs.",
		"enabled": not Game.has_grapple and Game.coins >= grapple_price,
	})
	items.append({
		"id": "gun", "name": "Blaster", "price": gun_price,
		"note": "1 draws it, hold left-click to fire, Shift to scope.",
		"enabled": not Game.has_gun and Game.coins >= gun_price,
	})
	items.append({
		"id": "ammo", "name": "Ammo  +%d" % ammo_per_purchase, "price": ammo_price,
		"note": "%d / %d rounds." % [Game.ammo, Game.max_ammo],
		"enabled": Game.has_gun and Game.coins >= ammo_price and Game.ammo < Game.max_ammo,
	})
	items.append({
		"id": "refill", "name": "Full Refill", "price": refill_price,
		"note": "Fill the blaster all the way to %d." % Game.max_ammo,
		"enabled": Game.has_gun and Game.coins >= refill_price and Game.ammo < Game.max_ammo,
	})
	items.append({
		"id": "reset", "name": "Standard Barrel", "price": reset_weapon_price,
		"note": "Strip any upgrade and put the blaster back to normal (now: %s)."
			% Game.weapon_mode.to_upper(),
		"enabled": Game.has_gun and Game.weapon_mode != "pellet" and Game.coins >= reset_weapon_price,
	})
	items.append({"id": "back", "name": "Back", "note": "", "enabled": true})
	return items

func _on_chosen(id: String) -> void:
	# Main-menu choices first; anything else is a shop purchase.
	match id:
		"shop":
			_open_shop()
			return
		"walk":
			_following = true
			_sitting = false
			Sfx.exotic()
			_menu.close()
			return
		"stop_walk":
			_following = false
			_home = global_position
			_enter_sit()
			_menu.close()
			return
		"leave":
			_menu.close()
			return
		"back":
			_menu.show_items(_main_items(), "What'll it be?", shop_name.to_upper())
			return
	var line := ""
	match id:
		"grapple":
			if not Game.has_grapple and Game.spend_coins(grapple_price):
				Game.has_grapple = true
				line = "Purrrr. Don't scratch the walls."
		"gun":
			if not Game.has_gun and Game.spend_coins(gun_price):
				Game.grant_gun()
				line = "Mrrow! Press 1 to draw it."
		"ammo":
			if Game.spend_coins(ammo_price):
				Game.collect_ammo(ammo_per_purchase)
				line = "*nudges the tin over*"
		"refill":
			if Game.ammo < Game.max_ammo and Game.spend_coins(refill_price):
				Game.collect_ammo(Game.max_ammo)
				line = "Topped right up. Mrrp."
		"reset":
			if Game.weapon_mode != "pellet" and Game.spend_coins(reset_weapon_price):
				Game.set_weapon_mode("pellet")
				line = "*swaps the barrel back* Standard again."
	if line != "":
		Sfx.exotic()
	# Rebuild the list so coins, ammo and the greyed-out rows are all current.
	_menu.show_items(_stock(), line if line != "" else "Mrrp?", "BISCUIT'S SHOP")

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
