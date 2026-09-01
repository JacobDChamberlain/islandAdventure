extends Control
# Title screen. Play starts the game, Quit exits. Enter/Space also starts.

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	$Menu/Play.pressed.connect(_start)
	$Menu/Quit.pressed.connect(func(): get_tree().quit())
	Sfx.wire_button($Menu/Play)
	Sfx.wire_button($Menu/Quit)
	$Menu/Play.grab_focus()

# Water drag: the ripple center chases the cursor via a spring so it lags behind
# and overshoots a touch when you stop (like momentum through water).
var _water_pos := Vector2(0.5, 0.5)
var _water_vel := Vector2.ZERO
const WATER_STIFFNESS := 65.0   # higher = snappier follow
const WATER_DAMPING := 11.0     # lower = more overshoot/fling

func _process(delta: float) -> void:
	var mat := $Bg.material as ShaderMaterial
	if mat == null:
		return
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var target := get_viewport().get_mouse_position() / size
	var dt: float = minf(delta, 0.05)   # clamp so a hitch can't explode the spring
	var accel := (target - _water_pos) * WATER_STIFFNESS - _water_vel * WATER_DAMPING
	_water_vel += accel * dt
	_water_pos += _water_vel * dt
	mat.set_shader_parameter("mouse", _water_pos)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_start()

func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
