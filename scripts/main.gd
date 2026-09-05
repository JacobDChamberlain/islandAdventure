extends Node3D
# Level root. Aims the sun, runs a day/night cycle, respawns defeated heads, and
# kicks off the run.

@export var day_length: float = 300.0    # seconds for a full day+night
@export var day_fraction: float = 0.75   # portion of the cycle that is daytime
@export var enemy_respawn_delay: float = 30.0   # seconds before a defeated head returns
# --- Blaster pickups scattered around the level (both levels use this script) ---
@export var ammo_crate_count: int = 14
@export var upgrade_kinds: Array[String] = ["rapid", "heavy", "laser", "bouncy"]
@export var upgrades_per_kind: int = 5   # one of each is far too few on a map this size
@export var upgrade_respawn_delay: float = 45.0  # a taken upgrade comes back elsewhere
@export var pickup_spread: float = 0.85    # fraction of the map radius to scatter within
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

	# Arrive in THIS world: its own artifacts/quest come back, your coins and
	# Exotic Matter carry over from wherever you've been.
	Game.enter_world(scene_file_path, get_tree().get_nodes_in_group("artifact").size())
	_restore_world_artifacts()
	SaveManager.apply_pending()

	_scatter_pickups()
	# Ammo and upgrades are pointless before you own the gun, so they only appear
	# once you've bought it — including mid-level, the moment you buy.
	Game.gun_acquired.connect(_scatter_pickups)

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

# Artifacts already found in this world stay found, and if its hunt was underway
# the remaining ones are revealed again.
func _restore_world_artifacts() -> void:
	for a in get_tree().get_nodes_in_group("artifact"):
		if String(a.name) in Game.collected_artifacts:
			a.queue_free()
	if Game.quest_active:
		Game.quest_started.emit()

# --- Blaster pickups ----------------------------------------------------------
# Ammo crates and weapon upgrades are placed procedurally rather than authored
# into each .tscn, so both the island and the city get them and the layout
# changes per playthrough. They only land on walkable ground.

func _scatter_pickups() -> void:
	if not Game.has_gun:
		return
	var ground := get_tree().get_first_node_in_group("island")
	if ground == null:
		return
	var radius: float = (ground.extent * pickup_spread) if "extent" in ground else 80.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ammo_script := load("res://scripts/ammo_pickup.gd")
	for i in ammo_crate_count:
		var spot := _walkable_spot(ground, rng, radius)
		if spot == Vector2.INF:
			continue
		var crate = ammo_script.new()
		add_child(crate)
		crate.global_position = Vector3(spot.x, 50.0, spot.y)
	for kind in upgrade_kinds:
		for i in upgrades_per_kind:
			_spawn_upgrade(kind)

# One upgrade, dropped somewhere walkable. Re-used for the initial scatter and
# for respawning a kind after the player takes it.
func _spawn_upgrade(kind: String) -> void:
	if not Game.has_gun:
		return
	var ground := get_tree().get_first_node_in_group("island")
	if ground == null:
		return
	var radius: float = (ground.extent * pickup_spread) if "extent" in ground else 80.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spot := _walkable_spot(ground, rng, radius)
	if spot == Vector2.INF:
		return
	var up = load("res://scripts/weapon_upgrade.gd").new()
	up.kind = kind
	up.collected.connect(_on_upgrade_taken)
	add_child(up)
	up.global_position = Vector3(spot.x, 50.0, spot.y)

# Taken upgrades come back after a while, somewhere else on the map.
func _on_upgrade_taken(kind: String) -> void:
	await get_tree().create_timer(upgrade_respawn_delay).timeout
	if is_inside_tree():
		_spawn_upgrade(kind)

# A random spot on dry, walkable ground — or Vector2.INF if we can't find one.
func _walkable_spot(ground: Node, rng: RandomNumberGenerator, radius: float) -> Vector2:
	for attempt in 40:
		var a := rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * radius        # even spread over the disc
		var p := Vector2(cos(a) * r, sin(a) * r)
		var ok := true
		if ground.has_method("is_walkable"):
			ok = ground.is_walkable(p.x, p.y)
		elif ground.has_method("height_at"):
			ok = ground.height_at(p.x, p.y) >= 1.5
		# Don't drop pickups inside a city building — the city reports every tile
		# walkable, so is_walkable alone happily buries them in a tower.
		if ok and ground.has_method("building_top_at") and ground.has_method("height_at"):
			if ground.building_top_at(p.x, p.y) > ground.height_at(p.x, p.y) + 0.5:
				ok = false
		if ok:
			return p
	return Vector2.INF

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
