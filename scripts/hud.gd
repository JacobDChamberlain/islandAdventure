extends Control
# On-screen display: a live 3D head portrait, a health bar, an artifact counter,
# and an Exotic Matter counter. It listens to the Game brain's signals and
# updates the widgets.

@onready var health_bar: ProgressBar = $HealthBar
@onready var artifact_label: Label = $ArtifactCount
@onready var exotic_label: Label = $ExoticCount
@onready var coin_label: Label = $CoinCount
@onready var lives_label: Label = $LivesLabel
@onready var portrait_rect: TextureRect = $Portrait
@onready var portrait_viewport: SubViewport = $PortraitViewport
@onready var damage_flash: ColorRect = $DamageFlash
@onready var toast_box: Control = $ToastBox
@onready var artifact_icon_rect: TextureRect = $ArtifactIcon
@onready var exotic_icon_rect: TextureRect = $ExoticIcon
@onready var coin_icon_rect: TextureRect = $CoinIcon
@onready var artifact_icon_vp: SubViewport = $ArtifactIconVP
@onready var exotic_icon_vp: SubViewport = $ExoticIconVP
@onready var coin_icon_vp: SubViewport = $CoinIconVP

var _last_health: int = 5

# Health bar fill colors (lerped from full -> empty).
const HEALTH_FULL := Color(0.35, 0.85, 0.4)
const HEALTH_LOW := Color(0.9, 0.25, 0.2)
# Pickup-toast colors (match the HUD counters).
const ARTIFACT_COLOR := Color(1.0, 0.82, 0.15)
const EXOTIC_COLOR := Color(0.74, 0.42, 1.0)

func _ready() -> void:
	# Show the mini-viewport's live render inside the circular portrait.
	portrait_rect.texture = portrait_viewport.get_texture()
	# Live 3D icons of each collectible model, rendered offscreen.
	artifact_icon_rect.texture = artifact_icon_vp.get_texture()
	exotic_icon_rect.texture = exotic_icon_vp.get_texture()
	coin_icon_rect.texture = coin_icon_vp.get_texture()

	_last_health = Game.health
	Game.score_changed.connect(_on_score_changed)
	Game.exotic_changed.connect(_on_exotic_changed)
	Game.coins_changed.connect(_on_coins_changed)
	_build_ammo_readout()
	Game.ammo_changed.connect(_on_ammo_changed)
	Game.weapon_mode_changed.connect(func(_m): _on_ammo_changed(Game.ammo, Game.max_ammo))
	Game.artifact_collected.connect(_on_artifact_collected)
	Game.exotic_collected.connect(_on_exotic_collected)
	Game.health_changed.connect(_on_health_changed)
	Game.lives_changed.connect(_on_lives_changed)
	damage_flash.color.a = 0.0
	call_deferred("_refresh")

func _flash_damage() -> void:
	damage_flash.color.a = 0.45
	var t := create_tween()
	t.tween_property(damage_flash, "color:a", 0.0, 0.45)

func _refresh() -> void:
	_on_score_changed(Game.score, Game.total_artifacts)
	_on_exotic_changed(Game.exotic_matter)
	_on_coins_changed(Game.coins)
	_on_ammo_changed(Game.ammo, Game.max_ammo)
	_on_health_changed(Game.health, Game.max_health)
	_on_lives_changed(Game.lives, Game.max_lives)

func _on_score_changed(score: int, total: int) -> void:
	artifact_label.text = "%d / %d" % [score, total]

func _on_exotic_changed(count: int) -> void:
	exotic_label.text = "%d" % count

func _on_coins_changed(count: int) -> void:
	coin_label.text = "%d" % count

func _on_health_changed(health: int, max_health: int) -> void:
	if health < _last_health:
		_flash_damage()
	_last_health = health
	health_bar.max_value = max_health
	health_bar.value = health
	var frac := float(health) / float(max(max_health, 1))
	# Recolor the fill from green (full) to red (low).
	var box := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if box:
		box.bg_color = HEALTH_LOW.lerp(HEALTH_FULL, frac)

func _on_lives_changed(lives: int, _max_lives: int) -> void:
	lives_label.text = "Lives   %d" % lives

# --- Pickup toasts ------------------------------------------------------------

func _on_artifact_collected(score: int, total: int) -> void:
	_spawn_toast("+  Artifact   %d / %d" % [score, total], ARTIFACT_COLOR)

func _on_exotic_collected(_count: int) -> void:
	_spawn_toast("+  Exotic Matter", EXOTIC_COLOR)

# A short-lived on-screen label that fades in, drifts up the screen, then fades
# out and frees. A soft colored halo (0-offset text shadow) gives it a glow.
# Several stack when you grab things in quick succession.
func _spawn_toast(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.2))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 5)
	# Colored, un-offset shadow with a fat outline = a soft glow around the text.
	l.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 16)
	toast_box.add_child(l)
	# Full screen width so centered text lands at screen center; stack new toasts
	# a little higher so rapid pickups don't overlap.
	l.size = Vector2(get_viewport_rect().size.x, 40)
	var start_y := -float(toast_box.get_child_count() - 1) * 34.0
	l.position = Vector2(0, start_y)
	l.modulate.a = 0.0
	var life := 1.55
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", start_y - 120.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 1.0, 0.12)
	t.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(life - 0.5)
	t.chain().tween_callback(l.queue_free)


# --- Blaster readout ----------------------------------------------------------
# Built in code so it appears in every level's HUD without editing each .tscn.
# Hidden entirely until the gun is bought.

var _ammo_label: Label
var _mode_label: Label
var _flash_tween: Tween

func _build_ammo_readout() -> void:
	_ammo_label = Label.new()
	# Pinned to the TOP-RIGHT (anchors, not fixed coords) so it never collides
	# with the Lives/coins column on the left, at any window size.
	_ammo_label.anchor_left = 1.0
	_ammo_label.anchor_right = 1.0
	_ammo_label.offset_left = -460.0
	_ammo_label.offset_right = -22.0
	_ammo_label.offset_top = 18.0
	_ammo_label.offset_bottom = 118.0
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.clip_text = false
	_ammo_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	_ammo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_ammo_label.add_theme_constant_override("outline_size", 10)
	_ammo_label.add_theme_font_size_override("font_size", 78)   # 3x — readable mid-fight
	_ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ammo_label.visible = false
	add_child(_ammo_label)

	# The fire mode goes on its own line underneath. Sharing one line with a
	# 3-digit count at 78pt ran the name past the edge of the screen ("BOUNCY"
	# lost its Y), and no sane box width fixes that for every mode name.
	_mode_label = Label.new()
	_mode_label.anchor_left = 1.0
	_mode_label.anchor_right = 1.0
	_mode_label.offset_left = -460.0
	_mode_label.offset_right = -22.0
	_mode_label.offset_top = 104.0
	_mode_label.offset_bottom = 140.0
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.clip_text = false
	_mode_label.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	_mode_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_mode_label.add_theme_constant_override("outline_size", 7)
	_mode_label.add_theme_font_size_override("font_size", 30)
	_mode_label.visible = false
	add_child(_mode_label)

func _on_ammo_changed(ammo: int, _max_ammo: int) -> void:
	if _ammo_label == null:
		return
	_ammo_label.visible = Game.has_gun
	_ammo_label.text = str(ammo)
	if _mode_label != null:
		# Only name the mode when it isn't the plain blaster.
		_mode_label.visible = Game.has_gun and Game.weapon_mode != "pellet"
		_mode_label.text = Game.weapon_mode.to_upper()
	# Red AND pulsing when empty, so running dry is impossible to miss.
	_ammo_label.add_theme_color_override("font_color",
		Color(1.0, 0.35, 0.35) if ammo <= 0 else Color(0.55, 0.95, 1.0))
	_set_empty_flash(ammo <= 0 and Game.has_gun)

func _set_empty_flash(on: bool) -> void:
	if on == (_flash_tween != null and _flash_tween.is_valid()):
		return                       # already in the right state
	if not on:
		if _flash_tween != null:
			_flash_tween.kill()
		_flash_tween = null
		_ammo_label.modulate.a = 1.0
		if _mode_label != null:
			_mode_label.modulate.a = 1.0
		return
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(_ammo_label, "modulate:a", 0.25, 0.35)
	_flash_tween.tween_property(_ammo_label, "modulate:a", 1.0, 0.35)
