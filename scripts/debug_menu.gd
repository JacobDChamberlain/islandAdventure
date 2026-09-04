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
	_status.text = "Artifacts %d / %d    Coins %d    Exotic %d    Lives %d/%d\nquest_active: %s    night: %s  (N toggles)" % [
		Game.score, Game.total_artifacts, Game.coins, Game.exotic_matter,
		Game.lives, Game.max_lives, str(Game.quest_active), str(Game.is_night)]
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
