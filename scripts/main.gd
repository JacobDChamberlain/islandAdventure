extends Node3D
# The root of the level. For now it just aims the sun. Later this becomes our
# "game manager" — spawning collectibles, tracking score, handling win/lose.

func _ready() -> void:
	# Point the sunlight down and across for nice shadows.
	$Sun.rotation_degrees = Vector3(-55, -35, 0)
