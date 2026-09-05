extends SceneTree
# Retarget a Mixamo animation onto the hero's 24-bone Meshy rig.
#
#   Godot --headless --path . --script tools/retarget_mixamo.gd ++ <source.fbx> <clip> <out.res>
#
# Deliberately NOT done via the import dock's BoneMap/Rest Fixer: that would mean
# editing hero_anim_merged.glb.import, and a mistake there breaks all 15 working
# clips. This writes a NEW animation resource instead — purely additive, and
# deleting the file undoes it completely.
#
# The maths. A bone's animated rotation only means anything relative to the rest
# pose it was authored on, so we take the DELTA from Mixamo's rest — but that
# delta is expressed in MIXAMO'S bone axes, and the two rigs orient their bones
# differently. Replaying it directly (hero_rest * delta) twists him inside out;
# that was the first attempt and it genuinely did.
#
# So convert the delta into the hero's bone frame first. With Sg and Hg the two
# rigs' GLOBAL rest rotations for that bone, the source's world-space motion is
# Sg·delta·Sg⁻¹, and the hero reproduces it locally with:
#
#     C = Hg⁻¹ · Sg
#     hero_local = hero_rest · (C · delta · C⁻¹)

const HERO := "res://assets/models/hero_anim_merged.glb"

# Mixamo name (prefix stripped) -> this rig's name. Only bones the hero actually
# has; the finger chains are dropped since he has none.
const NAME_MAP := {
	"Hips": "Hips",
	"Spine": "Spine", "Spine1": "Spine01", "Spine2": "Spine02",
	"Neck": "neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm",
	"LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightArm": "RightArm",
	"RightForeArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg",
	"LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase",
	"RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg",
	"RightFoot": "RightFoot", "RightToeBase": "RightToeBase",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("RETARGET usage: <source.fbx> <clip name> <out.res>")
		quit()
		return
	var src_path: String = args[0]
	var clip_name: String = args[1]
	var out_path: String = args[2]

	var src_skel := _skeleton_of(src_path)
	var hero_skel := _skeleton_of(HERO)
	if src_skel == null or hero_skel == null:
		print("RETARGET could not find a skeleton in both files")
		quit()
		return
	var src_anim := _clip_of(src_path, clip_name)
	if src_anim == null:
		print("RETARGET no clip named '", clip_name, "'")
		quit()
		return

	# Bone tracks must address the skeleton NODE, e.g. "Armature/Skeleton3D:Hips".
	# Writing ".:Hips" binds to nothing and the clip plays with the rig inert, so
	# take the prefix from one of the hero's own working clips rather than guess.
	var prefix := _skeleton_path_prefix()
	if prefix == "":
		print("RETARGET could not work out the skeleton path prefix")
		quit()
		return
	print("RETARGET writing tracks under '", prefix, "'")

	var out := Animation.new()
	out.length = src_anim.length
	out.loop_mode = Animation.LOOP_LINEAR
	var moved := 0
	# Rotation alone leaves the pelvis frozen and the legs flailing around it —
	# vertical motion (a hop, a crouch) lives in the Hips POSITION track. Convert
	# it too, scaled between the rigs, but pin X/Z so he performs on the spot
	# instead of wandering off (this project drives movement from code velocity).
	var scale := _hips_scale(hero_skel, src_skel)
	for ti in src_anim.get_track_count():
		if src_anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		var bpath := str(src_anim.track_get_path(ti))
		var bname := bpath.get_slice(":", 1).replace("mixamorig_", "").replace("mixamorig:", "")
		if bname != "Hips":
			continue
		var hips_i := hero_skel.find_bone("Hips")
		if hips_i < 0 or src_anim.track_get_key_count(ti) == 0:
			continue
		var rest_pos := hero_skel.get_bone_rest(hips_i).origin
		var first: Vector3 = src_anim.position_track_interpolate(ti, 0.0)
		var pt := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pt, NodePath("%s:Hips" % prefix))
		for ki in src_anim.track_get_key_count(ti):
			var t: float = src_anim.track_get_key_time(ti, ki)
			var v: Vector3 = src_anim.position_track_interpolate(ti, t)
			out.position_track_insert_key(pt, t,
				Vector3(rest_pos.x, rest_pos.y + (v.y - first.y) * scale, rest_pos.z))
		moved += 1
		print("RETARGET hips position converted (scale %.3f)" % scale)
	var skipped: Array[String] = []

	for ti in src_anim.get_track_count():
		if src_anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var path := str(src_anim.track_get_path(ti))
		var bone := path.get_slice(":", 1)
		var plain := bone.replace("mixamorig_", "").replace("mixamorig:", "")
		if not NAME_MAP.has(plain):
			skipped.append(plain)
			continue
		var hero_bone: String = NAME_MAP[plain]
		var hi := hero_skel.find_bone(hero_bone)
		var si := src_skel.find_bone(bone)
		if hi < 0 or si < 0:
			skipped.append(plain)
			continue

		var hero_rest := hero_skel.get_bone_rest(hi).basis.get_rotation_quaternion()
		var src_rest := src_skel.get_bone_rest(si).basis.get_rotation_quaternion()
		var c := _global_rest(hero_skel, hi).inverse() * _global_rest(src_skel, si)
		var c_inv := c.inverse()
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt, NodePath("%s:%s" % [prefix, hero_bone]))
		for ki in src_anim.track_get_key_count(ti):
			var t: float = src_anim.track_get_key_time(ti, ki)
			var q: Quaternion = src_anim.rotation_track_interpolate(ti, t)
			var delta := src_rest.inverse() * q
			out.rotation_track_insert_key(nt, t, hero_rest * (c * delta * c_inv))
		moved += 1

	var err := ResourceSaver.save(out, out_path)
	print("RETARGET %d bone tracks -> %s (err %d), %d source tracks ignored (fingers/extras)"
		% [moved, out_path, err, skipped.size()])
	quit()


# How much bigger this rig is than Mixamo's, from the hips' rest height.
func _hips_scale(hero: Skeleton3D, src: Skeleton3D) -> float:
	var h := hero.find_bone("Hips")
	var m := src.find_bone("mixamorig_Hips")
	if h < 0 or m < 0:
		return 1.0
	var hy: float = absf(hero.get_bone_rest(h).origin.y)
	var my: float = absf(src.get_bone_rest(m).origin.y)
	if my < 0.0001:
		return 1.0
	return hy / my


# A bone's rest rotation in SKELETON space: walk up the parents multiplying.
func _global_rest(skel: Skeleton3D, idx: int) -> Quaternion:
	var q := Quaternion.IDENTITY
	var i := idx
	while i >= 0:
		q = skel.get_bone_rest(i).basis.get_rotation_quaternion() * q
		i = skel.get_bone_parent(i)
	return q


# The node path the hero's existing animations use, e.g. "Armature/Skeleton3D".
func _skeleton_path_prefix() -> String:
	var res := load(HERO)
	if res == null:
		return ""
	for a in res.instantiate().find_children("*", "AnimationPlayer", true, false):
		for anim_name in a.get_animation_list():
			var clip: Animation = a.get_animation(anim_name)
			for ti in clip.get_track_count():
				var p := str(clip.track_get_path(ti))
				if ":" in p:
					return p.get_slice(":", 0)
	return ""


func _skeleton_of(path: String) -> Skeleton3D:
	var res := load(path)
	if res == null:
		return null
	for s in res.instantiate().find_children("*", "Skeleton3D", true, false):
		return s
	return null


func _clip_of(path: String, clip: String) -> Animation:
	var res := load(path)
	if res == null:
		return null
	for a in res.instantiate().find_children("*", "AnimationPlayer", true, false):
		if a.has_animation(clip):
			return a.get_animation(clip)
	return null
