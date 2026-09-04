extends Control
# In-game pause menu (Esc). Runs while the tree is paused. Has a main button
# list plus Settings and Save/Load-slot sub-panels.

@onready var _main: VBoxContainer = $Main
@onready var _settings: VBoxContainer = $SettingsPanel
@onready var _slots: VBoxContainer = $SlotsPanel
@onready var _vol: HSlider = $SettingsPanel/VolumeRow/VolumeSlider
@onready var _music: HSlider = $SettingsPanel/MusicRow/MusicSlider
@onready var _sens: HSlider = $SettingsPanel/SensRow/SensSlider
@onready var _full: CheckButton = $SettingsPanel/FullRow/FullCheck
@onready var _slots_title: Label = $SlotsPanel/SlotsTitle
@onready var _slot_btns: Array = [$SlotsPanel/Slot1, $SlotsPanel/Slot2, $SlotsPanel/Slot3]

var _slots_mode: String = "save"

func _ready() -> void:
	for b in [$Main/Resume, $Main/Save, $Main/Load, $Main/Settings, $Main/Restart, $Main/QuitTitle,
			$SettingsPanel/SettingsBack, $SlotsPanel/SlotsBack, _slot_btns[0], _slot_btns[1], _slot_btns[2]]:
		Sfx.wire_button(b)
	$Main/Resume.pressed.connect(_resume)
	$Main/Save.pressed.connect(_open_slots.bind("save"))
	$Main/Load.pressed.connect(_open_slots.bind("load"))
	$Main/Settings.pressed.connect(_open_settings)
	$Main/Restart.pressed.connect(_restart)
	$Main/QuitTitle.pressed.connect(_quit_title)
	$SettingsPanel/SettingsBack.pressed.connect(_show_main)
	$SlotsPanel/SlotsBack.pressed.connect(_show_main)
	for i in 3:
		_slot_btns[i].pressed.connect(_on_slot.bind(i + 1))
	_vol.value_changed.connect(func(v): Settings.set_volume(v))
	_music.value_changed.connect(func(v): Settings.set_music_volume(v))
	_sens.value_changed.connect(func(v): Settings.set_sensitivity(v))
	_full.toggled.connect(func(on): Settings.set_fullscreen(on))
	hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Game.shop_open:
			return   # the shop window handles Esc itself (it closes)
		if not visible:
			if get_tree().paused:
				return   # something else (e.g. the end screen) owns the pause
			_pause()
		elif _settings.visible or _slots.visible:
			_show_main()
		else:
			_resume()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	get_tree().paused = true
	show()
	_show_main()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume() -> void:
	get_tree().paused = false
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _show_main() -> void:
	_settings.hide()
	_slots.hide()
	_main.show()
	$Main/Resume.grab_focus()

func _open_settings() -> void:
	_vol.value = Settings.volume
	_music.value = Settings.music_volume
	_sens.value = Settings.sensitivity
	_full.button_pressed = Settings.fullscreen
	_main.hide()
	_slots.hide()
	_settings.show()
	_vol.grab_focus()

func _open_slots(mode: String) -> void:
	_slots_mode = mode
	_slots_title.text = "SAVE GAME" if mode == "save" else "LOAD GAME"
	_refresh_slots()
	_main.hide()
	_settings.hide()
	_slots.show()
	_slot_btns[0].grab_focus()

func _refresh_slots() -> void:
	for i in 3:
		var slot := i + 1
		_slot_btns[i].text = "Slot %d:    %s" % [slot, SaveManager.slot_summary(slot)]
		_slot_btns[i].disabled = _slots_mode == "load" and not SaveManager.has_slot(slot)

func _on_slot(slot: int) -> void:
	if _slots_mode == "save":
		SaveManager.save_to_slot(slot)
		_refresh_slots()
	elif SaveManager.has_slot(slot):
		SaveManager.load_slot(slot)

func _restart() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

func _quit_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")
