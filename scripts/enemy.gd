extends CharacterBody3D
# A simple patrolling enemy. It walks back and forth along its local X axis.
# Stomp its head (land on it while falling) to defeat it. Bump it any other way
# and it hits you.
#
# Collision setup (important): the enemy body sits on layer 2, and the player
# only collides with layer 1 — so the player passes THROUGH the enemy instead of
# standing on it. That lets us read the player's real falling speed to tell a
# stomp from a side-bump. All the contact detection is done by the Detector area.

@export var speed: float = 3.0
@export var patrol_distance: float = 6.0   # how far from the start it walks each way
@export var gravity: float = 30.0

var _start_x: float = 0.0
var _dir: float = 1.0

func _ready() -> void:
	_start_x = global_position.x
	$Detector.body_entered.connect(_on_detector_body_entered)
	_snap_to_ground()

func _snap_to_ground() -> void:
	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		global_position.y = island.height_at(global_position.x, global_position.z) + 1.2

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Turn around at the ends of the patrol.
	if global_position.x > _start_x + patrol_distance:
		_dir = -1.0
	elif global_position.x < _start_x - patrol_distance:
		_dir = 1.0

	velocity.x = _dir * speed
	velocity.z = 0.0
	move_and_slide()

func _on_detector_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	# Stomp = player is above the enemy AND moving downward.
	var from_above: bool = body.global_position.y > global_position.y + 0.5
	var falling: bool = body.velocity.y < 0.0
	if from_above and falling:
		body.bounce()
		_die()
	else:
		body.take_hit(global_position)

func _die() -> void:
	# TODO later: play a poof particle / sound here.
	queue_free()
