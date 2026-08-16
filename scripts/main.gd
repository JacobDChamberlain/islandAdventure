extends Node3D
# Level root. Aims the sun, runs a day/night cycle, and kicks off the run.

@export var day_length: float = 300.0   # seconds for a full day+night (5 min)
var _tod: float = 0.22                   # time of day, 0..1 (starts mid-morning)

@onready var _sun: DirectionalLight3D = $Sun
var _env: Environment
var _sky: ProceduralSkyMaterial

func _ready() -> void:
	_sun.directional_shadow_max_distance = 110.0
	_env = $WorldEnvironment.environment
	_sky = _env.sky.sky_material
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_update_day_night()

	# Fresh run (count the gems in the level), then apply a loaded save if any.
	Game.new_run(get_tree().get_nodes_in_group("gem").size())
	SaveManager.apply_pending()

func _process(delta: float) -> void:
	_tod = fposmod(_tod + delta / day_length, 1.0)
	_update_day_night()

func _update_day_night() -> void:
	var s := sin(_tod * TAU)                  # sun height: -1..1, peak at 0.25 (noon)
	var daylight := clampf(s * 1.1, 0.0, 1.0)
	var low := 1.0 - clampf(s, 0.0, 1.0)      # 1 near the horizon, 0 overhead

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
