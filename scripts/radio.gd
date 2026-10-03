extends Node
# City radio: plays a playlist on a loop, like a station, with the current song
# and artist in the bottom-right corner. main.gd adds this when the level's
# `radio` export is on (the city), in place of a single looping Music track.
#
# Songs are listed by hand rather than parsed from file names, because the names
# don't agree on an order ("Daft Punk - Revolution 909" is artist first, "Hand On
# The Scantron - Mux Mool" is title first). Leave `artist` empty if unknown and
# only the title shows. To add a song: drop the file in assets/audio and add a row.

const SONGS: Array[Dictionary] = [
	{"path": "res://assets/audio/Daft Punk - Revolution 909 (Official Audio).mp3",
		"title": "Revolution 909", "artist": "Daft Punk"},
	{"path": "res://assets/audio/Enter Sandman (Remastered).mp3",
		"title": "Enter Sandman", "artist": "Metallica"},
	{"path": "res://assets/audio/Hand On The Scantron - Mux Mool.mp3",
		"title": "Hand On The Scantron", "artist": "Mux Mool"},
	{"path": "res://assets/audio/CHICKEN BANANA.mp3",
		"title": "Chicken Banana", "artist": ""},
	{"path": "res://assets/audio/Existense Is Punishment.mp3",   # the city's old theme
		"title": "Existense Is Punishment", "artist": ""},
]

@export var volume_db: float = -5.0
@export var label_alpha: float = 0.55     # resting see-through-ness of the readout
@export var announce_time: float = 4.0    # seconds at full opacity when a song starts

var _player: AudioStreamPlayer
var _label: Label
var _order: Array[int] = []
var _at: int = -1
var _fade: Tween

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.volume_db = volume_db
	add_child(_player)
	_player.finished.connect(_next)
	_build_label()
	# Shuffle once, then go round in that order — a station, not a random pick
	# every time (which can repeat a song straight away).
	for i in SONGS.size():
		_order.append(i)
	_order.shuffle()
	_next()

func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5            # under the pause menu (10), over the HUD
	add_child(layer)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_top = 1.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = -520.0
	_label.offset_top = -92.0
	_label.offset_right = -18.0
	_label.offset_bottom = -44.0   # sits just above the controls line
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)

func _next() -> void:
	for attempt in SONGS.size():
		_at = (_at + 1) % _order.size()
		var song: Dictionary = SONGS[_order[_at]]
		var stream := load(song["path"]) as AudioStream
		if stream == null:
			continue                  # missing file: skip it rather than go silent
		if "loop" in stream:
			stream.loop = false       # mp3s import looping; a radio moves on
		_player.stream = stream
		_player.play()
		_show(song)
		return

func _show(song: Dictionary) -> void:
	var text: String = song["title"]
	if song["artist"] != "":
		text += "  ·  " + song["artist"]
	_label.text = "NOW PLAYING\n" + text
	if _fade:
		_fade.kill()
	_label.modulate.a = 1.0
	_fade = create_tween()
	_fade.tween_interval(announce_time)
	_fade.tween_property(_label, "modulate:a", label_alpha, 1.5)
