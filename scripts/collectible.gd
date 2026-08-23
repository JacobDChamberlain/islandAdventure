extends Area3D
# A pickup artifact. It spins and bobs to catch the eye, tells the Game brain it
# exists, and disappears (adding to your score) when the player touches it.

@export var spin_speed: float = 2.0
@export var bob_height: float = 0.35
@export var bob_speed: float = 2.5
@export var snap_to_ground: bool = true   # sit on the terrain at this x/z
@export var extra_height: float = 0.0      # float this far above it (for launch-pad artifacts)
@export var model_size: float = 0.9        # fit the Meshy model to this size (meters)
@export var glow_color: Color = Color(1.0, 0.72, 0.28)  # warm gold power glow
@export var glow_energy: float = 3.0       # how strongly the mesh self-illuminates (texture-modulated)
@export var brighten: float = 1.3          # lift the dark stone albedo (keep some stone darkness)

var _base_y: float = 0.0
var _time: float = 0.0
var _active: bool = false   # artifacts stay hidden until the Elder starts the quest

func _ready() -> void:
	add_to_group("artifact")
	_fit_model($Model, model_size)
	_apply_glow($Model)
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	Game.quest_started.connect(_on_quest_started)
	_snap_to_ground()
	_set_active(Game.quest_active)

# Show/hide + enable/disable pickup based on whether the quest is running.
func _set_active(on: bool) -> void:
	_active = on
	visible = on
	monitoring = on

func _on_quest_started() -> void:
	if not _active:
		_set_active(true)
		Fx.poof(global_position, Color(1.0, 0.82, 0.2), 18, 0.9)

# The generated artifact is dark brown stone; brighten its albedo and add a warm
# gold emission so it reads as a glowing power source (even at night).
func _apply_glow(model: Node3D) -> void:
	if model == null:
		return
	for m in model.find_children("*", "MeshInstance3D", true, false):
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
				# Modulate the glow by the stone texture so it keeps its detail
				# (dark crevices stay dark) instead of a flat solid-yellow wash.
				if bm.albedo_texture != null:
					bm.emission_texture = bm.albedo_texture
					bm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				mi.set_surface_override_material(i, bm)

# Auto-scale an imported Meshy model to `target` meters and center it on the
# pickup's origin, so it spins/bobs about its middle no matter how it was exported.
func _fit_model(model: Node3D, target: float) -> void:
	if model == null:
		return
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
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

func _snap_to_ground() -> void:
	if not snap_to_ground:
		_base_y = position.y
		return
	await get_tree().process_frame
	var island := get_tree().get_first_node_in_group("island")
	if island and island.has_method("height_at"):
		global_position.y = island.height_at(global_position.x, global_position.z) + 1.4 + extra_height
	_base_y = position.y

func _process(delta: float) -> void:
	_time += delta
	rotate_y(spin_speed * delta)
	position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if _active and body.is_in_group("player"):
		Fx.poof(global_position, Color(1.0, 0.82, 0.2), 16, 0.8)
		Sfx.artifact()
		Game.collect(name)
		queue_free()
