extends SubViewport
# A tiny offscreen 3D render of an item's model, shown in the HUD as its icon.
# Instances `model_scene` into the Stage, fits + centers it, lights it (own_world
# so it's isolated from the level), optionally adds a glow to match the in-world
# pickup, and slowly spins it. hud.gd points a TextureRect at get_texture().

@export var model_scene: PackedScene
@export var icon_size: float = 1.0          # fit the model to this many world units
@export var spin_speed: float = 0.8         # radians/sec
@export var glow_color: Color = Color(0, 0, 0, 0)   # a>0 = apply emission glow
@export var glow_energy: float = 2.5
@export var brighten: float = 1.3

var _model: Node3D

func _ready() -> void:
	var cam: Camera3D = $Stage/Camera3D
	cam.position = Vector3(0.0, 0.5, 2.7)
	cam.fov = 28.0
	cam.look_at(Vector3.ZERO, Vector3.UP)
	$Stage/Key.rotation_degrees = Vector3(-35, -25, 0)
	$Stage/Fill.rotation_degrees = Vector3(-12, 150, 0)
	if model_scene == null:
		return
	_model = model_scene.instantiate()
	$Stage.add_child(_model)
	_fit(_model, icon_size)
	if glow_color.a > 0.0:
		_apply_glow(_model)

func _process(delta: float) -> void:
	if _model:
		_model.rotate_y(spin_speed * delta)

func _fit(model: Node3D, target: float) -> void:
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	if meshes.is_empty():
		return
	var aabb: AABB
	var first := true
	var inv := model.global_transform.affine_inverse()
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := inv * mi.global_transform * mi.mesh.get_aabb()
		if first:
			aabb = local
			first = false
		else:
			aabb = aabb.merge(local)
	if first:
		return
	var biggest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if biggest <= 0.0:
		return
	var s := target / biggest
	model.scale = Vector3.ONE * s
	model.position = -aabb.get_center() * s

func _apply_glow(model: Node3D) -> void:
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null:
				continue
			var mat := src.duplicate()
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				bm.albedo_color = bm.albedo_color * brighten
				bm.emission_enabled = true
				bm.emission = glow_color
				bm.emission_energy_multiplier = glow_energy
				if bm.albedo_texture != null:
					bm.emission_texture = bm.albedo_texture
					bm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				mi.set_surface_override_material(i, bm)
