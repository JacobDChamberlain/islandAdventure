extends Control
# On-screen display: a live 3D head portrait, a health bar, and a gem counter.
# It listens to the Game brain's signals and updates the widgets.

@onready var health_bar: ProgressBar = $HealthBar
@onready var gem_label: Label = $GemCount
@onready var win_label: Label = $WinLabel
@onready var portrait_rect: TextureRect = $Portrait
@onready var portrait_viewport: SubViewport = $PortraitViewport

# Health bar fill colors (lerped from full -> empty).
const HEALTH_FULL := Color(0.35, 0.85, 0.4)
const HEALTH_LOW := Color(0.9, 0.25, 0.2)

func _ready() -> void:
	# Show the mini-viewport's live render inside the circular portrait.
	portrait_rect.texture = portrait_viewport.get_texture()

	Game.score_changed.connect(_on_score_changed)
	Game.health_changed.connect(_on_health_changed)
	Game.all_gems_collected.connect(_on_all_gems)
	win_label.hide()
	call_deferred("_refresh")

func _refresh() -> void:
	_on_score_changed(Game.score, Game.total_gems)
	_on_health_changed(Game.health, Game.max_health)

func _on_score_changed(score: int, total: int) -> void:
	gem_label.text = "%d / %d" % [score, total]

func _on_health_changed(health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	var frac := float(health) / float(max(max_health, 1))
	# Recolor the fill from green (full) to red (low).
	var box := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if box:
		box.bg_color = HEALTH_LOW.lerp(HEALTH_FULL, frac)

func _on_all_gems() -> void:
	win_label.show()
