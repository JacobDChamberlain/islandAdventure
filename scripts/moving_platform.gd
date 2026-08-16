extends AnimatableBody3D
# Oscillates between its start and start+travel, carrying anything standing on it
# (AnimatableBody3D + sync_to_physics does the carrying automatically).

@export var travel: Vector3 = Vector3(0, 6, 0)
@export var period: float = 4.0        # seconds for a full there-and-back
@export var base_offset: float = 1.0   # how high its low point sits above terrain

var _origin: Vector3
var _t: float = 0.0

func _ready() -> void:
	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		# Sit above the HIGHEST terrain under the platform's whole footprint along
		# the whole travel path, so no edge ever dips into a hill.
		var max_h := -1000.0
		for i in 7:
			var t := float(i) / 6.0
			var px := global_position.x + travel.x * t
			var pz := global_position.z + travel.z * t
			for ox in [-2.0, 0.0, 2.0]:
				for oz in [-2.0, 0.0, 2.0]:
					max_h = maxf(max_h, island.height_at(px + ox, pz + oz))
		global_position.y = max_h + base_offset
	_origin = position
	_t = randf() * period

func _physics_process(delta: float) -> void:
	_t += delta
	var f := sin(_t / period * TAU) * 0.5 + 0.5   # smooth 0..1..0
	position = _origin + travel * f
