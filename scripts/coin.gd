extends Area3D
# A coin. Common currency that heads scatter when defeated. Like Exotic Matter it
# pops out in an arc and can't be grabbed for a moment, so a burst of coins fans
# out and settles before you sweep them up. Spins (flips) and bobs; feeds
# Game.coins. No toast (coins are frequent) — just the counter + a bright "ching".

@export var spin_speed: float = 5.0
@export var bob_height: float = 0.15
@export var bob_speed: float = 3.5
@export var pop_up_speed: float = 6.0      # initial upward pop
@export var pop_side_speed: float = 3.2    # random horizontal scatter
@export var drop_gravity: float = 22.0
@export var rest_height: float = 1.0       # how high it floats above ground once settled
@export var arm_delay: float = 0.35        # can't be collected for this long after spawning

var _base_y: float = 0.0
var _time: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _grounded: bool = false
var _armed: bool = false
var _island: Node = null

func _ready() -> void:
	add_to_group("coin")
	body_entered.connect(_on_body_entered)
	var ang := randf() * TAU
	_vel = Vector3(cos(ang) * pop_side_speed, pop_up_speed, sin(ang) * pop_side_speed)
	await get_tree().process_frame
	_island = get_tree().get_first_node_in_group("island")
	get_tree().create_timer(arm_delay).timeout.connect(func() -> void: _armed = true)

func _process(delta: float) -> void:
	_time += delta
	rotate_y(spin_speed * delta)
	if _grounded:
		position.y = _base_y + sin(_time * bob_speed) * bob_height
		return
	_vel.y -= drop_gravity * delta
	global_position += _vel * delta
	var ground := rest_height
	if _island and _island.has_method("height_at"):
		ground = _island.height_at(global_position.x, global_position.z) + rest_height
	if global_position.y <= ground and _vel.y <= 0.0:
		global_position.y = ground
		_grounded = true
		_base_y = position.y

func _on_body_entered(body: Node3D) -> void:
	if _armed and body.is_in_group("player"):
		Fx.poof(global_position, Color(1.0, 0.85, 0.2), 8, 0.5)
		Sfx.coin()
		Game.collect_coin()
		queue_free()
