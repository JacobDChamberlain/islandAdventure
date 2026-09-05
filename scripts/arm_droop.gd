extends Node3D
# Lowers the hero's arms on top of whatever animation is playing.
#
# Meshy generated and auto-rigged him with his arms held out, and every clip was
# authored on that rig, so the raised arms live in the ANIMATION DATA. Godot's
# import-side "Fix Silhouette" can't help: with a BoneMap it retargets the tracks
# so he *looks the same* on a corrected rest pose, and preserving the motion is
# exactly what we don't want.
#
# This was first written as a SkeletonModifier3D, which is the "proper" node for
# the job — but its writes were silently discarded because the AnimationPlayer
# poses the skeleton AFTER the modifier stack runs, undoing them every frame.
# A plain node with a high process_priority is guaranteed to run last, so its
# writes are what the renderer sees. Set droop_deg to 0 to switch it off.

@export var droop_deg: float = 25.0                 # + lowers the arms, - raises them
@export var droop_axis: Vector3 = Vector3(0, 0, 1)  # local axis, measured off this rig
@export var mirror_right: bool = true               # right side needs the opposite sign
@export var left_bones: PackedStringArray = ["LeftArm"]
@export var right_bones: PackedStringArray = ["RightArm"]

var _skel: Skeleton3D


func _ready() -> void:
	_skel = get_parent() as Skeleton3D
	process_priority = 500      # after the AnimationPlayer has had its say


func _process(_delta: float) -> void:
	if _skel == null or is_zero_approx(droop_deg):
		return
	for b in left_bones:
		_turn(b, droop_deg)
	for b in right_bones:
		_turn(b, -droop_deg if mirror_right else droop_deg)


func _turn(bone: String, degrees: float) -> void:
	var i := _skel.find_bone(bone)
	if i < 0:
		return
	_skel.set_bone_pose_rotation(i,
		_skel.get_bone_pose_rotation(i) * Quaternion(droop_axis.normalized(), deg_to_rad(degrees)))
