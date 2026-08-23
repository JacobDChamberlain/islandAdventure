extends Control
# Shown on victory (all artifacts) or game over (out of lives). Pauses the game
# and offers Play Again / Quit to Title.

func _ready() -> void:
	Game.game_over.connect(_on_game_over)
	Game.all_artifacts_collected.connect(_on_victory)
	$VBox/PlayAgain.pressed.connect(_play_again)
	$VBox/QuitTitle.pressed.connect(_quit_title)
	Sfx.wire_button($VBox/PlayAgain)
	Sfx.wire_button($VBox/QuitTitle)
	hide()

func _on_game_over() -> void:
	_show("GAME OVER", Color(0.95, 0.25, 0.25))

func _on_victory() -> void:
	_show("YOU WIN!", Color(1.0, 0.85, 0.25))

func _show(txt: String, col: Color) -> void:
	if visible:
		return
	$VBox/Title.text = txt
	$VBox/Title.add_theme_color_override("font_color", col)
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$VBox/PlayAgain.grab_focus()

func _play_again() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

func _quit_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")
