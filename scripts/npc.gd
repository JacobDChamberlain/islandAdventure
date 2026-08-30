extends Node3D
# A stationary quest-giver ("the Elder"). Stand near it and press E to talk. The
# first conversation starts the Artifact hunt (Game.begin_quest → the artifacts
# appear); later talks report progress. Idle/talk animations play if the swapped-in
# model has them (fill anim_idle/anim_talk). Right now the model is a greybox
# capsule — drop the rigged .glb in as the "Model" child and set the clip names.

@export var npc_name: String = "Spencer"
@export var model_height: float = 1.9
@export var model_yaw_offset_deg: float = 180.0
@export var anim_idle: String = "Idle_3"
@export var anim_shock: String = "Electrocution_Reaction"   # talk mid-quest
@export var anim_excited: String = "Excited_Walk_M"         # finale part 1
@export var anim_backflip: String = "Backflip"             # finale part 2 → win

# Dialogue text — override per level for different flavor. The mid-quest line
# gets the live remaining count spliced in (see _talk).
@export_multiline var intro_lines: PackedStringArray = [
	"Ayy, fresh blood! Perfect timing. See, these islands are littered with Artifacts — old power cores, real deal stuff.",
	"Them nightmare heads are sittin' on 'em. Stomp 'em, deck 'em, fly-kick 'em, I don't care — just get the cores.",
	"Bring me the whole set and somethin' big opens up. Go on, get to work!",
]
@export_multiline var progress_hint: String = "Try the launch pads and the high platforms — the big heads hoard the good ones."
@export_multiline var complete_lines: PackedStringArray = [
	"No way... you actually got 'em ALL?!",
	"Ohhh it's happening, it's happening — watch THIS!",
]

var _anim: AnimationPlayer
var _player_near: bool = false
var _pending_begin: bool = false
var _complete_talk: bool = false   # this convo turned in the full set
var _in_finale: bool = false

@onready var prompt: Label3D = $Prompt

func _ready() -> void:
	add_to_group("npc")
	_add_body_collision()
	$TalkZone.body_entered.connect(_on_body_entered)
	$TalkZone.body_exited.connect(_on_body_exited)
	Dialogue.finished.connect(_on_dialogue_finished)
	prompt.visible = false
	await get_tree().process_frame
	_snap_to_ground()
	_setup_model()

# A solid body so the player/car can't walk or drive straight through the Elder.
func _add_body_collision() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = maxf(model_height, 1.2)
	cs.shape = shape
	cs.position.y = model_height * 0.5
	body.add_child(cs)
	add_child(body)

func _snap_to_ground() -> void:
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		global_position.y = island.height_at(global_position.x, global_position.z)

func _setup_model() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	_fit_model(model)
	_anim = model.get_node_or_null("AnimationPlayer")
	if _anim == null:
		return
	# Idle loops; the reaction/finale clips are one-shots we chain by hand.
	for clip in [anim_shock, anim_excited, anim_backflip]:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	_strip_root_motion(_anim)
	_anim.animation_finished.connect(_on_anim_finished)
	_play_idle()

func _play_idle() -> void:
	if _anim and anim_idle != "" and _anim.has_animation(anim_idle):
		_anim.get_animation(anim_idle).loop_mode = Animation.LOOP_LINEAR
		_anim.play(anim_idle)

# --- Interaction --------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = true
		if not Dialogue.active:
			prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = false
		prompt.visible = false

func _input(event: InputEvent) -> void:
	if not _player_near or Dialogue.active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		_talk()

func _talk() -> void:
	prompt.visible = false
	_face_player()
	Game.cinematic = true   # freeze the player + zoom the camera in for the chat
	if not Game.quest_active:
		_pending_begin = true
		Dialogue.start(npc_name, Array(intro_lines))
	elif not Game.artifacts_all_found():
		var left := Game.total_artifacts - Game.score
		if _anim and _anim.has_animation(anim_shock):
			_anim.play(anim_shock)
		Dialogue.start(npc_name, [
			"Bzzt— agh! Still %d Artifact%s out there, don't leave me hangin'!" % [left, "" if left == 1 else "s"],
			progress_hint,
		])
	else:
		_complete_talk = true
		Dialogue.start(npc_name, Array(complete_lines))

func _on_dialogue_finished() -> void:
	if _pending_begin:
		_pending_begin = false
		Game.begin_quest()
	if _complete_talk:
		_complete_talk = false
		_start_finale()
		return
	Game.cinematic = false
	_play_idle()
	if _player_near:
		prompt.visible = true

# Celebration: excited walk → (no pause) backflip → end the run.
func _start_finale() -> void:
	if _anim == null or not _anim.has_animation(anim_excited):
		Game.cinematic = false
		Game.complete_quest()
		return
	_in_finale = true
	_anim.play(anim_excited)
	# Crossfade into the backflip just before the walk ends, so there's no pause.
	if _anim.has_animation(anim_backflip):
		var lead := maxf(_anim.get_animation(anim_excited).length - 0.15, 0.05)
		await get_tree().create_timer(lead).timeout
		if is_instance_valid(self) and _in_finale:
			_anim.play(anim_backflip, 0.15)

func _on_anim_finished(finished_name: String) -> void:
	if _in_finale and finished_name == anim_backflip:
		_in_finale = false
		Game.cinematic = false
		Game.complete_quest()

# Turn the player to face the Elder so the zoomed camera frames the conversation.
func _face_player() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var target := Vector3(global_position.x, p.global_position.y, global_position.z)
	if target.distance_to(p.global_position) > 0.05:
		p.look_at(target, Vector3.UP)

# --- Model fitting (skeleton extent for rigged models, else mesh AABB) ---------

func _fit_model(model: Node3D) -> void:
	var aabb := _measure(model)
	if aabb.size.y <= 0.0:
		return
	var s := model_height / aabb.size.y
	model.scale = Vector3.ONE * s
	model.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	model.rotation_degrees.y = model_yaw_offset_deg

func _measure(model: Node3D) -> AABB:
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
	var result := AABB()
	var first2 := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := (model.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		if first2:
			result = box; first2 = false
		else:
			result = result.merge(box)
	return result

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
