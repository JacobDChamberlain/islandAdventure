extends Node3D
# Level root. Aims the sun, runs a day/night cycle, respawns defeated heads, and
# kicks off the run.

@export var day_length: float = 300.0    # seconds for a full day+night
@export var day_fraction: float = 0.75   # portion of the cycle that is daytime
@export var enemy_respawn_delay: float = 30.0   # seconds before a defeated head returns
var _tod: float = 0.16                    # time of day, 0..1 (starts mid-morning)

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

@onready var _sun: DirectionalLight3D = $Sun
var _env: Environment
var _sky: ProceduralSkyMaterial

func _ready() -> void:
	_sun.directional_shadow_max_distance = 110.0
	_env = $WorldEnvironment.environment
	_sky = _env.sky.sky_material
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_update_day_night()

	# Fresh run (count the artifacts in the level), then apply a loaded save if any.
	Game.new_run(get_tree().get_nodes_in_group("artifact").size())
	SaveManager.apply_pending()

	# Track the heads that start in the level so we can respawn them when stomped.
	for e in get_tree().get_nodes_in_group("enemy"):
		_register_enemy(e)

	# Fade the island music in over 5s (it starts silent at -40 dB).
	var music := get_node_or_null("Music") as AudioStreamPlayer
	if music:
		create_tween().tween_property(music, "volume_db", -5.0, 5.0)

func _process(delta: float) -> void:
	_tod = fposmod(_tod + delta / day_length, 1.0)
	_update_day_night()

# Warp the time-of-day so `day_fraction` of the cycle keeps the sun above the
# horizon: daytime is stretched and night is compressed. Returns sun height -1..1.
func _sun_height() -> float:
	var df: float = clampf(day_fraction, 0.05, 0.95)
	var theta: float
	if _tod < df:
		theta = (_tod / df) * PI               # 0..PI  → sun up (sin positive)
	else:
		theta = PI + ((_tod - df) / (1.0 - df)) * PI   # PI..TAU → sun down
	return sin(theta)

# Dev helper (DebugMenu: P then N): jump straight to midnight or back to
# mid-morning instead of waiting out the cycle to test night-time things.
func toggle_night() -> void:
	_tod = 0.16 if Game.is_night else 0.875
	_update_day_night()

func _update_day_night() -> void:
	var s := _sun_height()                    # sun height: -1..1, peak at midday
	var daylight := clampf(s * 1.1, 0.0, 1.0)
	var low := 1.0 - clampf(s, 0.0, 1.0)      # 1 near the horizon, 0 overhead

	# Heads hunt harder once the light drops toward dusk/night.
	Game.is_night = daylight < 0.15

	# Sun angle + light.
	_sun.rotation_degrees = Vector3(-(s * 80.0 + 10.0), -40.0, 0.0)
	_sun.light_energy = lerpf(0.03, 1.15, daylight)
	_sun.light_color = Color(1, 1, 1).lerp(Color(1.0, 0.55, 0.25), low * 0.9)

	# Sky colors (night → day, with a sunset tint near the horizon crossings).
	_sky.sky_top_color = Color(0.02, 0.02, 0.08).lerp(Color(0.32, 0.58, 0.9), daylight)
	var base_hor := Color(0.05, 0.04, 0.12).lerp(Color(0.72, 0.86, 0.96), daylight)
	var sunset_amt := clampf(1.0 - abs(s) * 4.0, 0.0, 1.0) * clampf(daylight + 0.3, 0.0, 1.0)
	_sky.sky_horizon_color = base_hor.lerp(Color(0.95, 0.45, 0.2), sunset_amt)

	# Ambient (kept bright enough at night to still see).
	_env.ambient_light_color = Color(0.16, 0.19, 0.32).lerp(Color(0.6, 0.64, 0.7), daylight)
	_env.ambient_light_energy = lerpf(0.4, 1.0, daylight)

# --- Enemy respawn ------------------------------------------------------------
# Heads come back: capture each head's placement + per-instance tuning, and when
# it dies, spawn a fresh copy at the same spot after a delay.

func _register_enemy(e: Node) -> void:
	var cfg := {
		"xform": e.transform,
		"yaw": e.model_yaw_offset_deg,
		"roam": e.roam_radius,
		"hp": e.max_hp,
	}
	e.died.connect(_on_enemy_died.bind(cfg))

func _on_enemy_died(cfg: Dictionary) -> void:
	await get_tree().create_timer(enemy_respawn_delay).timeout
	if not is_inside_tree():
		return
	var e := ENEMY_SCENE.instantiate()
	e.transform = cfg["xform"]        # heads are root-level, so local == world here
	e.model_yaw_offset_deg = cfg["yaw"]
	e.roam_radius = cfg["roam"]
	e.max_hp = cfg["hp"]
	add_child(e)
	_register_enemy(e)
