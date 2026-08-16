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

func _process(delta: float) -> void:
	_time += delta
	rotate_y(spin_speed * delta)
	position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		Game.add_score(1)
		queue_free()
