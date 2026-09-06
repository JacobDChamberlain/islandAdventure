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

# Snapshot every visible surface while something is rendering black.
#
# The first version only reported whether albedo_texture was non-null, which
# wasn't enough: Biscuit was captured mid-bug with a perfectly healthy material
# (tex=true, albedo white). A bound Texture2D says nothing about whether the
# RENDERING SERVER still holds its pixels — and a texture whose GPU-side RID has
# gone renders black while its material still looks fine.
#
# So each unique texture is now read back with get_image(), which asks the
# rendering server for the actual content. Three outcomes, three different bugs:
#   RS-DATA GONE  -> get_image() returned nothing: the GPU-side texture is dead
#   ALL BLACK     -> pixels came back black: the source data itself is black
#   fine          -> the texture is intact and the fault is elsewhere (lighting,
#                    shader, or the draw itself)
func _dump_materials() -> void:
	var lines: Array[String] = []
	# Counted in a Dictionary, not plain ints: GDScript lambdas capture locals by
	# VALUE, so increments inside `report` below would be thrown away.
	var n_cnt: Dictionary = {"total": 0, "suspect": 0}
	var seen: Dictionary = {}      # texture path -> verdict, so each is read once
	var fragile: Array[String] = []   # metallic=1 + no emission: reflection-only

	# Reading a texture back from the GPU is slow, hence the dedupe above.
	var check_tex := func(t: Texture2D) -> String:
		if t == null:
			return "none"
		var key: String = t.resource_path if t.resource_path != "" else str(t.get_instance_id())
		if seen.has(key):
			return seen[key]
		var verdict := ""
		var img: Image = null
		# A freed RID typically makes this return null rather than erroring.
		img = t.get_image()
		if img == null or img.is_empty():
			verdict = "RS-DATA GONE (%dx%d)" % [t.get_width(), t.get_height()]
		else:
			# These are VRAM-compressed, and get_pixel() can't read a compressed
			# image — it has to be decompressed first or every sample errors.
			if img.is_compressed():
				if img.decompress() != OK:
					seen[key] = "compressed, undecodable"
					return seen[key]
			# Sample a grid rather than every pixel; enough to tell black from art.
			var w := img.get_width()
			var h := img.get_height()
			var sum := 0.0
			var n := 0
			for gx in 8:
				for gy in 8:
					var c := img.get_pixel(int(w * gx / 8.0), int(h * gy / 8.0))
					sum += c.r + c.g + c.b
					n += 1
			var mean := sum / maxf(float(n) * 3.0, 1.0)
			if mean < 0.02:
				verdict = "ALL BLACK (%dx%d mean %.4f)" % [w, h, mean]
			else:
				verdict = "ok %dx%d mean %.3f fmt %d" % [w, h, mean, img.get_format()]
		seen[key] = verdict
		return verdict

	var report := func(node_name: String, idx: int, m: Material) -> void:
		n_cnt.total += 1
		if m == null:
			lines.append("%s surface %d: NO MATERIAL" % [node_name, idx])
			n_cnt.suspect += 1
			return
		var desc := "%s surface %d: %s" % [node_name, idx, m.get_class()]
		if m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			desc += "  albedo=%s metallic=%.2f rough=%.2f emission=%s" % [
				str(bm.albedo_color), bm.metallic, bm.roughness, str(bm.emission_enabled)]
			# Check EVERY texture slot, not just albedo. These Meshy materials are
			# metallic=1.0, which contributes no diffuse at all — what actually
			# makes them visible is the emission texture. So emission is the slot
			# whose loss renders a model solid black while albedo still measures
			# perfectly healthy, which is what the first capture showed.
			var bad := false
			for slot in [["albedo", bm.albedo_texture], ["emission", bm.emission_texture],
					["normal", bm.normal_texture], ["orm", bm.orm_texture]]:
				var t: Texture2D = slot[1]
				if t == null:
					continue
				var st: String = check_tex.call(t)
				desc += "\n        %-9s %s" % [slot[0] + ":", st]
				if t.resource_path != "":
					desc += "\n            %s" % t.resource_path
				if st.begins_with("RS-DATA") or st.begins_with("ALL BLACK"):
					bad = true
			# Fully-metallic-with-no-emission is FRAGILE, not broken: it still
			# shows albedo x ambient, so Reno's and the car look fine. It's
			# listed separately at the end rather than counted as suspicious --
			# 13 of these fire on a perfectly healthy scene and would bury a
			# real hit.
			if bm.metallic > 0.95 and not bm.emission_enabled:
				fragile.append("%s (%s)" % [node_name,
					bm.albedo_texture.resource_path.get_file() if bm.albedo_texture else "no tex"])
			var dark: bool = bm.albedo_color.r + bm.albedo_color.g + bm.albedo_color.b < 0.05
			if dark:
				desc += "\n        <-- ALBEDO COLOUR IS BLACK"
			if dark or bad:
				n_cnt.suspect += 1
		elif m is ShaderMaterial:
			var sm := m as ShaderMaterial
			var st: String = check_tex.call(sm.get_shader_parameter("albedo_tex") as Texture2D)
			desc += "  shader=%s albedo=%s\n        albedo_tex: %s" % [
				str(sm.shader.resource_path.get_file()) if sm.shader else "none",
				str(sm.get_shader_parameter("albedo_color")), st]
			if st.begins_with("RS-DATA") or st.begins_with("ALL BLACK"):
				n_cnt.suspect += 1
		lines.append(desc)

	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		for i in mi.mesh.get_surface_count():
			report.call(String(mi.name), i, mi.get_active_material(i))
	# The buildings and foliage are MultiMesh, which the first version missed
	# entirely — and the ground going black was one of the reported symptoms.
	for mm in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
		if mm.multimesh == null or mm.multimesh.mesh == null or not mm.is_visible_in_tree():
			continue
		for i in mm.multimesh.mesh.get_surface_count():
			var m: Material = mm.material_override
			if m == null:
				m = mm.multimesh.mesh.surface_get_material(i)
			report.call("[MM] " + String(mm.name), i, m)

	# Never overwrite an earlier capture: the last report cost a press because
	# the second dump replaced the first.
	var n := 1
	while FileAccess.file_exists("user://black_report_%d.txt" % n):
		n += 1
	var path := "user://black_report_%d.txt" % n
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		var extra := ""
		if not fragile.is_empty():
			extra = "\n\n%s\nFULLY METALLIC, NO EMISSION (%d) -- these have no diffuse\nresponse, so they show only reflection/ambient. Not broken, but they\nare the first things that would go black if reflections fail:\n  %s" % [
				"-".repeat(60), fragile.size(), "\n  ".join(fragile)]
		f.store_string("scene: %s   night: %s\n%s\n\n%s%s" % [
			get_tree().current_scene.scene_file_path if get_tree().current_scene else "?",
			str(Game.is_night), "-".repeat(60), "\n".join(lines), extra])
		f.close()
	print("[debug] %d surfaces, %d suspicious -> %s" % [n_cnt.total, n_cnt.suspect, path])
	_status.text += "\nReport %d written (%d surfaces, %d suspicious)" % [
		n, n_cnt.total, n_cnt.suspect]

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
