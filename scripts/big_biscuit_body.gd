extends CharacterBody3D
# Big Biscuit's hittable body, built by cat.gd for the boss fight. Biscuit
# herself is a plain Node3D with no collider, so this stands in for her: it sits
# on the same layers as a kaiju (2 = punches, kicks, bullets and the car's ram;
# 3 = the grapple's aim ray) and joins group "enemy", so every existing way of
# hurting a head works on her with no changes to the player, gun or car.
# The player only collides with layer 1, so he passes through her like a head.

var cat: Node = null
# The grapple aims at `global_position + model_height * 0.5 * scale.y`, plus a
# bit — the crown of a kaiju whose origin is at its middle. Ours is at her FEET,
# so cat.gd sets this to twice her height, and the hook lands on top of her.
var model_height: float = 2.0

func _ready() -> void:
	collision_layer = 2 | 4
	collision_mask = 0
	add_to_group("enemy")

func hit_by_player(_from_pos: Vector3, _knockback: float, damage: int = 1) -> void:
	if cat and cat.has_method("boss_hit"):
		cat.boss_hit(damage)
