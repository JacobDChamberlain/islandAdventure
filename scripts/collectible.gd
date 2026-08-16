extends Area3D
# A pickup gem. It spins and bobs to catch the eye, tells the Game brain it
# exists, and disappears (adding to your score) when the player touches it.

@export var spin_speed: float = 2.0
@export var bob_height: float = 0.35
@export var bob_speed: float = 2.5

var _base_y: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	Game.register_gem()
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	_snap_to_ground()

func _snap_to_ground() -> void:
	# Sit just above the terrain wherever the gem was placed.
	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		global_position.y = island.height_at(global_position.x, global_position.z) + 1.4
	_base_y = position.y

func _process(delta: float) -> void:
	_time += delta
	rotate_y(spin_speed * delta)
	position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		Game.add_score(1)
		queue_free()
