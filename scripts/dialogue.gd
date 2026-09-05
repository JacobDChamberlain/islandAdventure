extends CanvasLayer
# A simple text dialogue box (autoload `Dialogue`). Call start(speaker, lines) to
# show a sequence of lines; press E / Space to advance. Emits `finished` when the
# last line is dismissed. Voiced audio can hang off this later. NPCs drive it and
# react to `finished`.

signal finished
signal confirmed(accepted: bool)   # emitted by ask() when the player picks Yes/No
signal line_shown(index: int)      # each time a new line appears (drives NPC cutaways)

@onready var panel: Control = $Panel
@onready var speaker_label: Label = $Panel/Margin/VBox/Speaker
@onready var body_label: Label = $Panel/Margin/VBox/Body
@onready var hint_label: Label = $Panel/Margin/VBox/Hint

var active: bool = false
var _lines: Array = []
var _idx: int = 0
var _opened_frame: int = -1   # so the E that opens the box doesn't also advance it
var _confirm: bool = false    # last line is a Yes/No question (ask())

# Typewriter reveal + GBA-style speech blips.
const REVEAL_SPEED := 38.0     # characters per second
var _revealing: bool = false
var _reveal_chars: float = 0.0
var _prev_visible: int = 0
var _since_blip: int = 0

func _ready() -> void:
	panel.visible = false

func start(speaker: String, lines: Array) -> void:
	_confirm = false
	_begin(speaker, lines)

# Like start(), but the LAST line is a Yes/No question: emits confirmed(bool).
func ask(speaker: String, lines: Array) -> void:
	_confirm = true
	_begin(speaker, lines)

func _begin(speaker: String, lines: Array) -> void:
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
	_update_hint()
	line_shown.emit(_idx)

func _update_hint() -> void:
	if hint_label == null:
		return
	if _confirm and _idx == _lines.size() - 1:
		hint_label.text = "[E] Yes      [Q] No"
	else:
		hint_label.text = "Press Enter to continue"

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
	if _confirm and _idx == _lines.size() - 1:
		return   # on the question line: wait for Yes/No in _input
	_idx += 1
	if _idx >= _lines.size():
		_close()
	else:
		_show_current()

func _close() -> void:
	active = false
	panel.visible = false
	finished.emit()

func _finish_confirm(accepted: bool) -> void:
	_confirm = false
	active = false
	panel.visible = false
	confirmed.emit(accepted)

func _input(event: InputEvent) -> void:
	if not active or Engine.get_frames_drawn() == _opened_frame:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kc: int = event.physical_keycode
	# On a confirm's fully-revealed question line: E/Enter/Y = Yes, Q/Esc/N = No.
	if _confirm and not _revealing and _idx == _lines.size() - 1:
		if kc in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_Y, KEY_SPACE]:
			_finish_confirm(true)
			get_viewport().set_input_as_handled()
		elif kc in [KEY_Q, KEY_N, KEY_ESCAPE, KEY_BACKSPACE]:
			_finish_confirm(false)
			get_viewport().set_input_as_handled()
		return
	if kc in [KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE]:
		advance()
		get_viewport().set_input_as_handled()
