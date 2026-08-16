extends Node
# Global sound helper. Loads sound variants once and plays a random one (with a
# little pitch variation) through a pool of players so sounds can overlap.
# Player SFX: Sfx.stomp(), Sfx.gem(), Sfx.hurt(), Sfx.jump(), Sfx.footstep().
# Enemies grab streams directly via random_step()/random_weird() to play them
# from their own positional (3D) audio players.

const IMPACT := "res://assets/audio/kenney_impact-sounds/Audio/"
const INTERFACE := "res://assets/audio/kenney_interface-sounds/Audio/"
const SCIFI := "res://assets/audio/kenney_sci-fi-sounds/Audio/"
# Short, punchy sci-fi sounds used as the heads' "weird noises" (skips the long
# engine/thruster drones).
const WEIRD_BASES := ["forceField", "laserRetro", "laserSmall", "slime", "impactMetal"]

var _stomp: Array[AudioStream] = []
var _gem: Array[AudioStream] = []
var _hurt: Array[AudioStream] = []
var _step: Array[AudioStream] = []
var _jump: Array[AudioStream] = []
var _weird: Array[AudioStream] = []

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	_stomp = _variants(IMPACT + "impactSoft_heavy")
	_hurt = _variants(IMPACT + "impactWood_heavy")
	_gem = _variants(INTERFACE + "select")
	_step = _variants(IMPACT + "footstep_grass")
	_jump = _variants(IMPACT + "impactSoft_medium")
	for base in WEIRD_BASES:
		_weird.append_array(_variants(SCIFI + base))
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func _no_loop(s: AudioStream) -> AudioStream:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	return s

# Numbered variants of a base name (…_000 … _009) that exist.
func _variants(base: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for i in range(0, 10):
		var path := "%s_%03d.ogg" % [base, i]
		if ResourceLoader.exists(path):
			out.append(_no_loop(load(path)))
	return out

# Every audio file under a directory (recursive) — used for the drop-in weird pack.
func _load_dir(dir_path: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if name != "." and name != "..":
				out.append_array(_load_dir(full))
		elif name.ends_with(".ogg") or name.ends_with(".wav") or name.ends_with(".mp3"):
			if ResourceLoader.exists(full):
				out.append(_no_loop(load(full)))
		name = d.get_next()
	d.list_dir_end()
	return out

func _play(bank: Array[AudioStream], volume_db: float, pitch_var: float) -> void:
	if bank.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = bank[randi() % bank.size()]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()

func stomp() -> void: _play(_stomp, 0.0, 0.15)
func gem() -> void: _play(_gem, -3.0, 0.1)
func hurt() -> void: _play(_hurt, 1.0, 0.12)
func footstep() -> void: _play(_step, -9.0, 0.22)
func jump() -> void: _play(_jump, -5.0, 0.1)

# For enemies to play from their own 3D audio players.
func random_step() -> AudioStream:
	return _step[randi() % _step.size()] if not _step.is_empty() else null

func random_weird() -> AudioStream:
	return _weird[randi() % _weird.size()] if not _weird.is_empty() else null
