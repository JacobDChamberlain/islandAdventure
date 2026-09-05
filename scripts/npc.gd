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
@export var finale_walk_time: float = 0.7   # excited walk before crossfading to the flip

# Dialogue text — override per level for different flavor. The mid-quest line
# gets the live remaining count spliced in (see _talk).
@export_multiline var intro_lines: PackedStringArray = [
	"Ayy, fresh blood! Perfect timing. See, these islands are littered with Artifacts — old power cores, real deal stuff.",
	"Them nightmare heads are sittin' on 'em. Stomp 'em, deck 'em, fly-kick 'em, I don't care — just get the cores.",
	"Bring me the whole set and somethin' big opens up. Go on, get to work!",
]
# Idle chatter that floats over his head whenever you're stood nearby, cycling
# on a timer. Separate from the E prompt, which now sits at waist height.
@export_multiline var idle_bubble_lines: PackedStringArray = [
	"Heyy mann, I'm gonna have to ask you to leave. Ha ha, I'm just playin'.",
	"I am gonna need to see some I.D. tho.",
]
# Each line is held for bubble_seconds PLUS time per character, so a long line
# gets long enough to read and a short one doesn't linger.
@export var bubble_seconds: float = 2.0
@export var bubble_seconds_per_char: float = 0.035
@export var bubble_pause: float = 9.0       # then he shuts up for this long
@export var bubble_range: float = 10.5      # 3x the E-prompt zone, so he calls out early
@export var bubble_height: float = 2.5

# Pestering him before you've finished. One is picked at random; {left}, {have}
# and {total} are filled in, so the numbers stay true however many there are.
@export_multiline var mid_quest_lines: PackedStringArray = [
	"Hey bud, listen man, come back when you have {total} Artifacts, and we can talk.",
	"Chill bro. Chill. {left} Artifacts left.",
	"Hey listen man ain't I already tell you? Artifacts. Bro. You got like {have}. Come back when you have all {total}.",
	"Bro.",
	"Bro chill.",
]

# While this intro line is on screen, cut away to Artifacts out in the world.
@export var cutaway_line: int = 1
@export var cutaway_shots: int = 3
@export var cutaway_hold: float = 2.0
@export var cutaway_high_first: bool = false   # city: show the rooftop ones
@export var cutaway_distance: float = 3.2

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
var _bubble: Label3D
var _bubble_bg: MeshInstance3D
var _bubble_idx: int = 0
var _talking_intro: bool = false   # true only during the quest-giving speech
var _bubble_t: float = 0.0
var _rng := RandomNumberGenerator.new()

# --- Artifact cutaway ---
var _cut_cam: Camera3D
var _cut_targets: Array[Node3D] = []
var _cut_idx: int = 0
var _cut_t: float = 0.0
var _cut_revealed: Array[Node3D] = []   # artifacts we forced visible for the shot

@onready var prompt: Label3D = $Prompt

func _ready() -> void:
	add_to_group("npc")
	_add_body_collision()
	$TalkZone.body_entered.connect(_on_body_entered)
	$TalkZone.body_exited.connect(_on_body_exited)
	Dialogue.finished.connect(_on_dialogue_finished)
	Dialogue.line_shown.connect(_on_line_shown)
	_rng.randomize()
	_build_bubble()
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

func _build_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.position = Vector3(0.0, bubble_height, 0.0)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.pixel_size = 0.005
	_bubble.font_size = 40
	_bubble.outline_size = 12
	_bubble.modulate = Color(1, 1, 1)
	_bubble.outline_modulate = Color(0, 0, 0)
	_bubble.width = 520.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble.visible = false
	add_child(_bubble)

	# Label3D has no background, and pale text over grass or concrete is unreadable.
	# A billboarded quad behind it, drawn first via render_priority, gives him a
	# speech bubble without needing an image.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.06, 0.06, 0.09, 0.72)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.render_priority = -1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bubble_bg = MeshInstance3D.new()
	_bubble_bg.mesh = quad
	_bubble_bg.material_override = mat
	_bubble_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble_bg.visible = false
	add_child(_bubble_bg)
	_bubble.render_priority = 2
	_bubble.outline_render_priority = 1

func _process(delta: float) -> void:
	_step_bubble(delta)
	_step_cutaway(delta)

func _step_bubble(delta: float) -> void:
	if _bubble == null:
		return
	# Its own radius, independent of the E-prompt zone, so he pipes up well
	# before you're close enough to talk.
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var near := p != null and p.global_position.distance_to(global_position) <= bubble_range
	if not near or Dialogue.active or Game.cinematic or idle_bubble_lines.is_empty():
		_bubble.visible = false
		_bubble_bg.visible = false
		_bubble_idx = 0
		_bubble_t = 0.0
		return

	# Say both lines, then go quiet for bubble_pause before starting over.
	_bubble_t += delta
	if _bubble_idx < idle_bubble_lines.size():
		if _bubble_t >= _bubble_hold():
			_bubble_t = 0.0
			_bubble_idx += 1
	elif _bubble_t >= bubble_pause:
		_bubble_t = 0.0
		_bubble_idx = 0

	var talking := _bubble_idx < idle_bubble_lines.size()
	_bubble.visible = talking
	_bubble_bg.visible = talking
	if talking:
		_bubble.text = idle_bubble_lines[_bubble_idx]
		_fit_bubble_bg()

# How long the current line stays up — longer lines get more reading time.
func _bubble_hold() -> float:
	if _bubble_idx >= idle_bubble_lines.size():
		return bubble_pause
	return bubble_seconds + float(idle_bubble_lines[_bubble_idx].length()) * bubble_seconds_per_char

# Size the panel to the TEXT, measured from the font. Label3D.get_aabb() reports
# the layout box — the whole wrap width — which made the panel a huge slab.
func _fit_bubble_bg() -> void:
	var f: Font = _bubble.font
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return
	var px: Vector2 = f.get_multiline_string_size(_bubble.text,
		HORIZONTAL_ALIGNMENT_CENTER, _bubble.width, _bubble.font_size)
	var quad: QuadMesh = _bubble_bg.mesh
	quad.size = Vector2(px.x * _bubble.pixel_size + 0.22, px.y * _bubble.pixel_size + 0.16)
	_bubble_bg.position = _bubble.position

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
		_talking_intro = true
		Dialogue.start(npc_name, _filled(intro_lines))
	elif not Game.artifacts_all_found():
		if _anim and _anim.has_animation(anim_shock):
			_anim.play(anim_shock)
		Dialogue.start(npc_name, [_mid_quest_line()])
	else:
		_complete_talk = true
		Dialogue.start(npc_name, Array(complete_lines))

# --- Artifact cutaways ------------------------------------------------------
# While a chosen intro line is on screen we cut to real Artifacts standing out in
# the level: a temporary camera flies to each in turn, holds, then moves on, and
# the view returns to Spencer when the line changes. Live in-engine, so the shots
# match the current time of day and only ever show orbs still out there.

func _on_line_shown(index: int) -> void:
	if not Dialogue.active or not _talking_intro:
		return
	if index == cutaway_line:
		_begin_cutaway()
	else:
		_end_cutaway()

func _begin_cutaway() -> void:
	_cut_targets = _pick_cutaway_targets()
	if _cut_targets.is_empty():
		return
	if _cut_cam == null:
		_cut_cam = Camera3D.new()
		_cut_cam.fov = 55.0
		get_tree().current_scene.add_child(_cut_cam)
	_cut_idx = 0
	_cut_t = 0.0
	_frame_shot()
	_cut_cam.current = true

# Artifacts hide until the quest starts, so on the island they would be invisible
# during this very speech — reveal the ones we film and put them back after.
func _pick_cutaway_targets() -> Array[Node3D]:
	var all: Array[Node3D] = []
	for a in get_tree().get_nodes_in_group("artifact"):
		if a is Node3D and is_instance_valid(a):
			all.append(a)
	if all.is_empty():
		return all
	if cutaway_high_first:
		all.sort_custom(func(x, y): return x.global_position.y > y.global_position.y)
	else:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null:
			all.sort_custom(func(x, y):
				return x.global_position.distance_to(p.global_position) \
					< y.global_position.distance_to(p.global_position))
	var picked: Array[Node3D] = []
	for a in all:
		picked.append(a)
		if not a.visible:
			a.visible = true
			_cut_revealed.append(a)
		if picked.size() >= cutaway_shots:
			break
	return picked

func _step_cutaway(delta: float) -> void:
	if _cut_cam == null or not _cut_cam.current or _cut_targets.is_empty():
		return
	_cut_t += delta
	if _cut_t >= cutaway_hold:
		_cut_t = 0.0
		_cut_idx = (_cut_idx + 1) % _cut_targets.size()
	_frame_shot()

# Slow orbit so the shot has some life in it.
func _frame_shot() -> void:
	var a: Node3D = _cut_targets[_cut_idx]
	if not is_instance_valid(a):
		return
	var ang: float = _cut_t * 0.4 + float(_cut_idx) * 2.1
	var at := a.global_position
	_cut_cam.global_position = at + Vector3(cos(ang) * cutaway_distance, 1.0,
		sin(ang) * cutaway_distance)
	_cut_cam.look_at(at, Vector3.UP)

func _end_cutaway() -> void:
	if _cut_cam != null and _cut_cam.current:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null:
			var pc := p.get_node_or_null("CameraPivot/Camera3D") as Camera3D
			if pc != null:
				pc.current = true      # hand the view back to the conversation
		_cut_cam.current = false
	# Only re-hide artifacts if the quest still hasn't started.
	if not Game.quest_active:
		for a in _cut_revealed:
			if is_instance_valid(a):
				a.visible = false
	_cut_revealed.clear()
	_cut_targets.clear()

# One of the pestering lines, with {left}/{have}/{total} filled in.
func _mid_quest_line() -> String:
	if mid_quest_lines.is_empty():
		return progress_hint
	return _subst(mid_quest_lines[_rng.randi() % mid_quest_lines.size()])

# Fill {grapple} in any line, so the city's price can't drift from the shop's.
func _filled(lines: PackedStringArray) -> Array:
	var price := 25
	for c in get_tree().get_nodes_in_group("cat"):
		if "grapple_price" in c:
			price = c.grapple_price
			break
	var out: Array = []
	for l in lines:
		out.append(_subst(str(l)).replace("{grapple}", str(price)))
	return out

# Every line gets the same treatment, so "{total}" can't leak into the box.
func _subst(line: String) -> String:
	return line.replace("{left}", str(Game.total_artifacts - Game.score)) \
		.replace("{have}", str(Game.score)) \
		.replace("{total}", str(Game.total_artifacts))

func _on_dialogue_finished() -> void:
	_talking_intro = false
	_end_cutaway()
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
	# Only a beat of the excited walk before the flip. Playing both at once would
	# need an AnimationTree blend; a fast crossfade gets the same read for free.
	if _anim.has_animation(anim_backflip):
		var lead: float = clampf(finale_walk_time, 0.0,
			maxf(_anim.get_animation(anim_excited).length - 0.1, 0.05))
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
