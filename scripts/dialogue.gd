extends CanvasLayer
# A simple text dialogue box (autoload `Dialogue`). Call start(speaker, lines) to
# show a sequence of lines; press E / Space to advance. Emits `finished` when the
# last line is dismissed. Voiced audio can hang off this later. NPCs drive it and
# react to `finished`.

signal finished

@onready var panel: Control = $Panel
@onready var speaker_label: Label = $Panel/Margin/VBox/Speaker
@onready var body_label: Label = $Panel/Margin/VBox/Body

var active: bool = false
var _lines: Array = []
var _idx: int = 0
var _opened_frame: int = -1   # so the E that opens the box doesn't also advance it

func _ready() -> void:
	panel.visible = false

func start(speaker: String, lines: Array) -> void:
	_lines = lines
	_idx = 0
	active = true
	_opened_frame = Engine.get_frames_drawn()
	speaker_label.text = speaker
	_show_current()
	panel.visible = true

func _show_current() -> void:
	body_label.text = str(_lines[_idx]) if _idx < _lines.size() else ""

func advance() -> void:
	_idx += 1
	if _idx >= _lines.size():
		_close()
	else:
		_show_current()

func _close() -> void:
	active = false
	panel.visible = false
	finished.emit()

func _input(event: InputEvent) -> void:
	if not active or Engine.get_frames_drawn() == _opened_frame:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_E or event.physical_keycode == KEY_SPACE):
		advance()
		get_viewport().set_input_as_handled()
