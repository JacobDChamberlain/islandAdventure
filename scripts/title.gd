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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_start()

func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
