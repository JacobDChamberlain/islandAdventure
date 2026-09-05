extends CanvasLayer
# Dev-only debug overlay (autoload `DebugMenu`). Press P in a level to toggle it.
# Lets you fast-forward the quest — set how many artifacts you've "collected",
# or complete the quest outright (which opens the island portal / wins the city)
# — and top up resources, so you can test late-game states without grinding.
# Only active while a level is loaded (there's a player in the tree).

var _open := false
@onready var _panel: Control = $Panel
@onready var _status: Label = $Panel/Margin/VBox/Status
@onready var _count: SpinBox = $Panel/Margin/VBox/CountRow/Count

func _ready() -> void:
	_panel.visible = false
	_count.value_changed.connect(_on_count_changed)
	$Panel/Margin/VBox/CollectAll.pressed.connect(_collect_all)
	$Panel/Margin/VBox/Complete.pressed.connect(_complete_quest)
	$Panel/Margin/VBox/ResRow/Coins.pressed.connect(func(): Game.collect_coin(10); _refresh())
	$Panel/Margin/VBox/ResRow/Exotic.pressed.connect(func(): Game.collect_exotic(1); _refresh())
	$Panel/Margin/VBox/ResRow/Life.pressed.connect(_add_life)
	$Panel/Margin/VBox/ResRow/Heal.pressed.connect(func(): Game.revive(); _refresh())
	$Panel/Margin/VBox/GoRow/GoCity.pressed.connect(func(): _goto("res://scenes/city.tscn"))
	$Panel/Margin/VBox/GoRow/GoIsland.pressed.connect(func(): _goto("res://scenes/main.tscn"))
	$Panel/Margin/VBox/WeaponRow/RemoveUpgrade.pressed.connect(_remove_upgrade)
	$Panel/Margin/VBox/WeaponRow/GiveGun.pressed.connect(_give_gun)
	$Panel/Margin/VBox/Reset.pressed.connect(_reset_run)

func _in_level() -> bool:
	return get_tree().get_first_node_in_group("player") != null

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_P:
		_toggle()
		get_viewport().set_input_as_handled()
	# N (while this panel is open) flips between midnight and morning, so you can
	# test night-time things without waiting out the day/night cycle.
	# B (panel open) — snapshot every visible material to user://black_report.txt.
	# For catching the intermittent "asset renders solid black" bug: press it WHILE
	# something is black and the report says whether the texture is actually
	# missing, the albedo is black, or the material looks fine (making it a
	# GPU/upload problem rather than a data one).
	elif _open and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_B:
		_dump_materials()
		get_viewport().set_input_as_handled()
	elif _open and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_N:
		var level := get_tree().current_scene
		if level and level.has_method("toggle_night"):
			level.toggle_night()
			_refresh()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if not _open and not _in_level():
		return   # only meaningful inside a level
	_open = not _open
	_panel.visible = _open
	if _open:
		_refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _in_level() and not get_tree().paused and not Dialogue.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh() -> void:
	_status.text = "Artifacts %d / %d    Coins %d    Exotic %d    Lives %d/%d\nquest_active: %s    night: %s  (N toggles)\ngun: %s    ammo %d    mode %s" % [
		Game.score, Game.total_artifacts, Game.coins, Game.exotic_matter,
		Game.lives, Game.max_lives, str(Game.quest_active), str(Game.is_night),
		str(Game.has_gun), Game.ammo, Game.weapon_mode]
	_count.max_value = maxi(Game.total_artifacts, 0)
	_count.set_value_no_signal(Game.score)

# --- Actions ------------------------------------------------------------------

func _set_score(v: int) -> void:
	Game.score = clampi(v, 0, Game.total_artifacts)
	Game.score_changed.emit(Game.score, Game.total_artifacts)
	Game.artifact_collected.emit(Game.score, Game.total_artifacts)
	_refresh()

func _on_count_changed(v: float) -> void:
	_set_score(int(v))

func _collect_all() -> void:
	_set_score(Game.total_artifacts)

# Instantly finish the quest: start it if needed, mark every artifact collected,
# then complete it — the island reveals its portal; the city shows the win.
func _complete_quest() -> void:
	if not Game.quest_active:
		Game.begin_quest()
	_set_score(Game.total_artifacts)
	Game.complete_quest()
	_refresh()

# Put the blaster back to its standard barrel (undo a rapid/heavy/laser pickup).
func _remove_upgrade() -> void:
	Game.set_weapon_mode("pellet")
	_refresh()

func _give_gun() -> void:
	Game.grant_gun()
	Game.collect_ammo(Game.max_ammo)
	_refresh()

func _dump_materials() -> void:
	var lines: Array[String] = []
	var suspect := 0
	var total := 0
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		for i in mi.mesh.get_surface_count():
			var m = mi.get_active_material(i)
			total += 1
			if m == null:
				lines.append("%s surface %d: NO MATERIAL" % [mi.name, i])
				suspect += 1
				continue
			var desc := "%s surface %d: %s" % [mi.name, i, m.get_class()]
			if m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				var dark: bool = bm.albedo_color.r + bm.albedo_color.g + bm.albedo_color.b < 0.05
				var no_tex: bool = bm.albedo_texture == null
				desc += "  albedo=%s tex=%s emission=%s" % [
					str(bm.albedo_color), str(not no_tex), str(bm.emission_enabled)]
				if dark:
					desc += "   <-- ALBEDO IS BLACK"
					suspect += 1
			elif m is ShaderMaterial:
				var sm := m as ShaderMaterial
				desc += "  shader=%s albedo=%s tex=%s" % [
					str(sm.shader.resource_path.get_file()) if sm.shader else "none",
					str(sm.get_shader_parameter("albedo_color")),
					str(sm.get_shader_parameter("albedo_tex") != null)]
			lines.append(desc)
	var f := FileAccess.open("user://black_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
	print("[debug] %d visible surfaces, %d suspicious -> user://black_report.txt" % [total, suspect])
	_status.text += "\nMaterial report written (%d surfaces, %d suspicious)" % [total, suspect]

func _add_life() -> void:
	Game.lives = mini(Game.lives + 1, Game.max_lives)
	Game.lives_changed.emit(Game.lives, Game.max_lives)
	_refresh()

func _reset_run() -> void:
	Game.new_run(Game.total_artifacts)
	_refresh()

# Jump straight to a level (skips talking to the Elder + walking to the portal).
func _goto(scene_path: String) -> void:
	_open = false
	_panel.visible = false
	get_tree().paused = false
	Game.cinematic = false
	Game.driving = false
	get_tree().change_scene_to_file(scene_path)
