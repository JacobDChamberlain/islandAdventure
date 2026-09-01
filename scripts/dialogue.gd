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

# Typewriter reveal + GBA-style speech blips.
const REVEAL_SPEED := 38.0     # characters per second
var _revealing: bool = false
var _reveal_chars: float = 0.0
var _prev_visible: int = 0
var _since_blip: int = 0

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
	var line: String = str(_lines[_idx]) if _idx < _lines.size() else ""
	body_label.text = line
	body_label.visible_characters = 0
	_reveal_chars = 0.0
	_prev_visible = 0
	_since_blip = 0
	_revealing = line.length() > 0

func _process(delta: float) -> void:
	if not active or not _revealing:
		return
	var full := body_label.text.length()
	_reveal_chars += REVEAL_SPEED * delta
	var vis: int = mini(int(_reveal_chars), full)
	if vis > _prev_visible:
		var text := body_label.text
		for i in range(_prev_visible, vis):
			var ch := text[i]
			if ch != " " and ch != "\n" and ch != "\t":
				_since_blip += 1
				if _since_blip >= 2:   # a blip every couple of letters
					_since_blip = 0
					Sfx.speak()
		_prev_visible = vis
		body_label.visible_characters = vis
	if vis >= full:
		_revealing = false
		body_label.visible_characters = -1   # show the whole line

func advance() -> void:
	if _revealing:
		# First press finishes the line instantly instead of advancing.
		body_label.visible_characters = -1
		_revealing = false
		return
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
			and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE]:
		advance()
		get_viewport().set_input_as_handled()
