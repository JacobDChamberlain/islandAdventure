extends AnimatableBody3D
# Oscillates between its start and start+travel, carrying anything on top of it
# (AnimatableBody3D + sync_to_physics does the carrying). All setup happens on the
# first physics frame — an AnimatableBody3D's transform is driven by the physics
# server, so positions set from _ready() don't stick.

@export var travel: Vector3 = Vector3(0, 6, 0)
@export var period: float = 4.0        # seconds for a full there-and-back
@export var base_offset: float = 1.0   # clearance above the highest ground on its path

var _origin: Vector3
var _t: float = 0.0
var _init: bool = false

func _physics_process(delta: float) -> void:
	if not _init:
		_init = true
		var base_y := position.y
		var island := get_tree().get_first_node_in_group("island")
		if island and island.has_method("height_at"):
			# Sit above the highest terrain under the platform's footprint along its path.
			var max_h := -1000.0
			for i in 7:
				var t := float(i) / 6.0
				var px := position.x + travel.x * t
				var pz := position.z + travel.z * t
				for ox in [-2.0, 0.0, 2.0]:
					for oz in [-2.0, 0.0, 2.0]:
						max_h = maxf(max_h, island.height_at(px + ox, pz + oz))
			base_y = max_h + base_offset
		_origin = Vector3(position.x, base_y, position.z)
		position = _origin   # full-vector assignment (subscript writes don't stick here)
		_t = randf() * period
		return

	_t += delta
	var f := sin(_t / period * TAU) * 0.5 + 0.5   # smooth 0..1..0
	position = _origin + travel * f
