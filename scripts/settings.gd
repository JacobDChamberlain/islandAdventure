extends Node
# Global settings, persisted to user://settings.cfg. Applied on startup and
# whenever changed from the Settings panel.

const PATH := "user://settings.cfg"

var volume: float = 0.8         # 0..1 master volume
var music_volume: float = 0.85   # 0..1 music-bus volume (relative to master)
var sensitivity: float = 1.0    # multiplier on the player's base mouse sensitivity
var fullscreen: bool = false

func _ready() -> void:
	_load()
	apply_all()

func _input(event: InputEvent) -> void:
	# Press F anywhere to toggle fullscreen.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		set_fullscreen(not fullscreen)

func apply_all() -> void:
	set_volume(volume, false)
	set_music_volume(music_volume, false)
	set_fullscreen(fullscreen, false)
	_save()

func set_volume(v: float, save: bool = true) -> void:
	volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(max(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	if save: _save()

func set_music_volume(v: float, save: bool = true) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(max(music_volume, 0.0001)))
		AudioServer.set_bus_mute(bus, music_volume <= 0.001)
	if save: _save()

func set_sensitivity(v: float, save: bool = true) -> void:
	sensitivity = clampf(v, 0.1, 4.0)
	if save: _save()

func set_fullscreen(on: bool, save: bool = true) -> void:
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if save: _save()

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("settings", "volume", volume)
	c.set_value("settings", "music_volume", music_volume)
	c.set_value("settings", "sensitivity", sensitivity)
	c.set_value("settings", "fullscreen", fullscreen)
	c.save(PATH)

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		volume = c.get_value("settings", "volume", 0.8)
		music_volume = c.get_value("settings", "music_volume", 0.85)
		sensitivity = c.get_value("settings", "sensitivity", 1.0)
		fullscreen = c.get_value("settings", "fullscreen", false)
