extends VehicleBody3D
# A greybox drivable car (city only). Parked in the world: walk up and press E to
# drive, E again to hop out beside it, R to flip it back upright. Grounded
# VehicleBody3D feel (real suspension + wheel grip). Swap the box "Body" for a
# Meshy car model later.

@export var engine_power: float = 1900.0     # forward drive force
@export var reverse_power: float = 1100.0     # reverse drive force
@export var max_steer: float = 0.45           # radians of steering lock
@export var steer_speed: float = 3.0          # how fast the wheels turn to target
@export var brake_force: float = 18.0         # handbrake + braking when reversing direction
@export var coast_brake: float = 2.5          # light auto-brake when off the throttle
@export var cam_back: float = 9.0             # chase camera distance behind
@export var cam_up: float = 4.0               # chase camera height
@export var cam_look_ahead: float = 1.2       # look at this height on the car
@export var mouse_orbit: float = 0.005        # camera orbit per mouse pixel while driving
@export var air_level_strength: float = 6.0   # how hard the car self-rights in the air
@export var air_spin_damp: float = 0.04        # airborne angular-velocity retention per frame (lower = stops spin faster)
@export var yaw_recover: float = 4.0           # extra yaw damping on the ground when not steering
@export var roll_recover: float = 7.0          # anti-roll strength (keeps wheels down in turns / rights it)

# Ramming
@export var ram_min_speed: float = 8.0         # min speed (m/s) to hurt a head
@export var ram_knockback: float = 16.0        # shove force on a rammed head

# Audio
@export var engine_min_pitch: float = 0.55
@export var engine_max_pitch: float = 1.9
@export var speed_ref: float = 26.0           # speed (m/s) mapped to max engine pitch

var _driver: Node = null       # the player node while driving (null = parked)
var _near: Node = null         # player currently inside the enter zone

# Chase-cam orbit offset (mouse), decays back to behind-the-car when idle.
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _mouse_idle: float = 0.0
var _upside_timer: float = 0.0

@onready var cam: Camera3D = $ChaseCam
@onready var prompt: Label3D = $Prompt
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("vehicle")
	cam.top_level = true
	cam.current = false
	prompt.visible = false
	$EnterZone.body_entered.connect(_on_enter_zone)
	$EnterZone.body_exited.connect(_on_exit_zone)
	$Ram.body_entered.connect(_on_ram)
	_setup_audio()
	await get_tree().process_frame
	var g := get_tree().get_first_node_in_group("island")
	if g and g.has_method("height_at"):
		global_position.y = g.height_at(global_position.x, global_position.z) + 0.8

func _setup_audio() -> void:
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = _looping("res://assets/audio/kenney_sci-fi-sounds/Audio/spaceEngineLow_000.ogg")
	_engine.unit_size = 12.0
	_engine.max_distance = 60.0
	_engine.volume_db = -8.0
	add_child(_engine)
	_skid = AudioStreamPlayer3D.new()
	_skid.stream = _looping("res://assets/audio/kenney_sci-fi-sounds/Audio/computerNoise_000.ogg")
	_skid.unit_size = 10.0
	_skid.max_distance = 45.0
	_skid.volume_db = -60.0
	add_child(_skid)

func _looping(path: String) -> AudioStream:
	var s := load(path)
	if s is AudioStreamOggVorbis:
		s.loop = true
	return s

func _on_enter_zone(body: Node) -> void:
	if body.is_in_group("player"):
		_near = body
		if _driver == null:
			prompt.visible = true

func _on_exit_zone(body: Node) -> void:
	if body == _near:
		_near = null
		prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	# Mouse orbit while driving.
	if _driver != null and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw = clampf(_cam_yaw - event.relative.x * mouse_orbit, -PI * 0.85, PI * 0.85)
		_cam_pitch = clampf(_cam_pitch - event.relative.y * mouse_orbit, -0.5, 0.65)
		_mouse_idle = 0.0
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_E:
		if _driver == null:
			if _near and not Dialogue.active and not Game.cinematic:
				_board(_near)
		else:
			_unboard()
	elif event.physical_keycode == KEY_R and _driver != null:
		_recover()

func _board(player: Node) -> void:
	_driver = player
	prompt.visible = false
	Game.driving = true
	_cam_yaw = 0.0
	_cam_pitch = 0.0
	# Never let the car physically collide with the player — while driving we ride
	# co-located with the (hidden) hero, and re-enabling its collision on exit used
	# to eject the car at orbital speed. Both still collide with the world.
	add_collision_exception_with(player)
	if player.has_method("board_vehicle"):
		player.board_vehicle()
	cam.global_position = global_position - _forward() * cam_back + Vector3.UP * cam_up
	cam.look_at(global_position + Vector3.UP * cam_look_ahead, Vector3.UP)   # face the car at once
	cam.current = true
	_engine.play()
	Sfx.jump()

func _unboard() -> void:
	var player := _driver
	_driver = null
	Game.driving = false
	engine_force = 0.0
	_engine.stop()
	_skid.stop()
	# Drop the hero on the ground beside the driver's door.
	var side := global_position + global_transform.basis.x * 3.0
	var g := get_tree().get_first_node_in_group("island")
	if g and g.has_method("height_at"):
		side.y = g.height_at(side.x, side.z) + 2.0
	if player and player.has_method("unboard_vehicle"):
		player.unboard_vehicle(side)
	if _near == player:
		prompt.visible = true

# Flip the car back upright, keeping its heading, and drop it just above the road.
func _recover() -> void:
	var g := get_tree().get_first_node_in_group("island")
	# Clamp back onto the map so a car that drove off the edge lands on real ground
	# instead of falling forever (which used to trap the rider in a drop loop).
	var limit := 230.0
	if g and "extent" in g:
		limit = g.extent - 24.0
	var x := clampf(global_position.x, -limit, limit)
	var z := clampf(global_position.z, -limit, limit)
	var gy := global_position.y
	if g and g.has_method("height_at"):
		gy = g.height_at(x, z)
	global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), Vector3(x, gy + 2.0, z))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

# The car's visual forward (the way it drives on W). The chase cam sits opposite
# this. It's +Z here (not the usual -Z) — that's the side the box body drives.
# Ram a head: fast enough kills the small ones and dents the big kaiju. Reuses the
# enemy's hit_by_player so a lethal ram drops loot just like a stomp.
func _on_ram(body: Node) -> void:
	if _driver == null or not (body is Node) or not body.is_in_group("enemy"):
		return
	if not body.has_method("hit_by_player"):
		return
	var speed := linear_velocity.length()
	if speed < ram_min_speed:
		return
	var dmg := clampi(int(speed / 5.0) + 1, 2, 8)   # >=2 kills small heads; dents kaiju
	body.hit_by_player(global_position, ram_knockback + speed * 0.6, dmg)
	Sfx.hit()
	Fx.poof(body.global_position, Color(0.9, 0.7, 0.3), 22, 2.4)

# Flung upward by a blue launch pad (same contract as the player's launch()).
func launch(strength: float) -> void:
	linear_velocity.y = strength

func _forward() -> Vector3:
	return global_transform.basis.z

func _physics_process(delta: float) -> void:
	# Safety net: if the car ever falls through the world, drop it back on the road
	# (works whether or not anyone's driving — R only works while seated).
	if global_position.y < -20.0:
		_recover()
		return

	if _driver == null:
		# Parked: hold it in place so it doesn't creep on the gentle slopes.
		engine_force = 0.0
		brake = 2.0
		steering = move_toward(steering, 0.0, steer_speed * delta)
		return

	_stabilize(delta)
	# Keep the (hidden) hero riding along so enemies track the CAR, not the spot
	# where you got in.
	if is_instance_valid(_driver):
		_driver.global_position = global_position

	var throttle := _axis(KEY_W, KEY_S)   # W=+1 forward, S=-1 reverse
	var vel_fwd := linear_velocity.dot(_forward())   # signed speed along travel-forward
	engine_force = 0.0
	brake = 0.0
	if Input.is_physical_key_pressed(KEY_SPACE):
		brake = brake_force                          # handbrake
	elif throttle > 0.0:
		if vel_fwd < -1.0:
			brake = brake_force                      # braking out of reverse → snappy flip
		else:
			engine_force = throttle * engine_power
	elif throttle < 0.0:
		if vel_fwd > 1.0:
			brake = brake_force                      # braking out of forward → snappy flip
		else:
			engine_force = throttle * reverse_power   # negative → reverse
	else:
		brake = coast_brake                          # gentle engine-braking on release

	# Speed-sensitive steering: tighten the lock as you go faster so it isn't twitchy.
	var speed := linear_velocity.length()
	var steer_limit := max_steer * lerpf(1.0, 0.45, clampf(speed / 24.0, 0.0, 1.0))
	var steer_in := _axis(KEY_A, KEY_D)
	steering = move_toward(steering, steer_in * steer_limit, steer_speed * delta)

	_auto_recover(delta)
	_update_audio(Input.is_physical_key_pressed(KEY_SPACE))
	_update_cam(delta)

func _axis(pos_key: int, neg_key: int) -> float:
	return (1.0 if Input.is_physical_key_pressed(pos_key) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(neg_key) else 0.0)

# GTA-style stability: in the air, bleed spin fast and self-right; on the ground,
# add yaw damping when you're not steering so a slide recovers quickly.
func _stabilize(delta: float) -> void:
	var grounded := 0
	for w in [$WheelFL, $WheelFR, $WheelRL, $WheelRR]:
		if (w as VehicleWheel3D).is_in_contact():
			grounded += 1
	var up := global_transform.basis.y
	var tilt := up.angle_to(Vector3.UP)
	if grounded == 0:
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - pow(air_spin_damp, delta))
		angular_velocity += up.cross(Vector3.UP) * air_level_strength * delta
	else:
		if absf(_axis(KEY_A, KEY_D)) < 0.1:
			# On the ground and not actively steering — damp leftover yaw (spin).
			var yaw_rate := angular_velocity.dot(up)
			angular_velocity -= up * yaw_rate * clampf(yaw_recover * delta, 0.0, 1.0)
		# Continuous anti-roll bar: constantly resist body roll so hard turns keep
		# all four wheels down (correction scales with how far it's tipped).
		if tilt > deg_to_rad(4.0):
			angular_velocity += up.cross(Vector3.UP) * roll_recover * delta

# If we end up on our roof and nearly stopped, right the car after a moment.
func _auto_recover(delta: float) -> void:
	var upright := global_transform.basis.y.dot(Vector3.UP)
	if upright < -0.2 and linear_velocity.length() < 1.5:
		_upside_timer += delta
		if _upside_timer > 2.5:
			_recover()
			_upside_timer = 0.0
	else:
		_upside_timer = 0.0

func _update_audio(braking: bool) -> void:
	var speed := linear_velocity.length()
	var lateral := absf(linear_velocity.dot(global_transform.basis.x))
	# Engine: pitch + a little volume rise with speed.
	var t := clampf(speed / speed_ref, 0.0, 1.0)
	_engine.pitch_scale = lerpf(engine_min_pitch, engine_max_pitch, t)
	_engine.volume_db = lerpf(-10.0, -3.0, t)
	# Skid: sideways slip (drift) or hard braking while moving.
	var skid := clampf((lateral - 3.0) / 7.0, 0.0, 1.0)
	if braking and speed > 5.0:
		skid = maxf(skid, 0.6)
	if skid > 0.06:
		if not _skid.playing:
			_skid.play()
		_skid.volume_db = lerpf(-28.0, -7.0, skid)
		_skid.pitch_scale = lerpf(0.8, 1.25, skid)
	elif _skid.playing:
		_skid.stop()

func _update_cam(delta: float) -> void:
	# Let mouse orbit the cam; when the mouse goes idle, ease back behind the car.
	_mouse_idle += delta
	if _mouse_idle > 0.35:
		_cam_yaw = lerpf(_cam_yaw, 0.0, 1.0 - pow(0.02, delta))
		_cam_pitch = lerpf(_cam_pitch, 0.0, 1.0 - pow(0.02, delta))
	var dir := Basis(Vector3.UP, _cam_yaw) * _forward()
	var target := global_position - dir * cam_back + Vector3.UP * (cam_up + _cam_pitch * 6.0)
	# Keep the camera out of walls/buildings.
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, target)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		target = hit.position + (from - target).normalized() * 0.5
	# Never let the camera sit on top of the car (a zero-length look_at → NaN → a
	# broken/solid-colour frame).
	if target.distance_to(global_position) < 2.5:
		target = global_position + (target - global_position).normalized() * 2.5 + Vector3.UP * 0.5
	cam.global_position = cam.global_position.lerp(target, 1.0 - pow(0.0001, delta))
	var look_target := global_position + Vector3.UP * cam_look_ahead
	if cam.global_position.distance_to(look_target) > 0.05:
		cam.look_at(look_target, Vector3.UP)
