extends Area3D
# A weapon upgrade lying out in the world. Walking into it swaps the blaster's
# fire mode for the rest of the level (Game.weapon_mode; the modes themselves
# live in weapon.gd's MODES table).
#
# Upgrades are per-level on purpose: new_run resets the mode back to "pellet",
# so finding the laser in the city doesn't carry back to the island.

signal collected(kind: String)

@export var kind: String = "rapid"           # must match a key in weapon.gd MODES
@export var model: PackedScene = null        # optional Meshy replacement
@export var spin_speed: float = 2.0
@export var bob_height: float = 0.2
@export var bob_speed: float = 2.0
@export var rest_height: float = 1.2
@export var beacon_height: float = 26.0   # sky-beam so you can find it from afar

# Greybox look + the pickup toast, per upgrade.
const LOOKS := {
	"rapid": {"color": Color(0.6, 1.0, 0.7), "name": "RAPID FIRE"},
	"heavy": {"color": Color(1.0, 0.7, 0.35), "name": "HEAVY SLUG"},
	"laser": {"color": Color(1.0, 0.32, 0.48), "name": "LASER"},
	"bouncy": {"color": Color(0.85, 0.55, 1.0), "name": "BOUNCY"},
	"pellet": {"color": Color(0.55, 0.95, 1.0), "name": "BLASTER"},
}

var _base_y: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	add_to_group("upgrade")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	collision_mask = 1
	_build_visual()
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	shape.shape = sph
	add_child(shape)
	_snap_to_ground()

func _look() -> Dictionary:
	return LOOKS.get(kind, LOOKS["pellet"])

func _build_visual() -> void:
	if model != null:
		add_child(model.instantiate())
		return
	# A glowing floating gem, tinted by which upgrade it is.
	var prism := PrismMesh.new()
	prism.size = Vector3(0.7, 1.0, 0.7)
	var mat := StandardMaterial3D.new()
	var col: Color = _look()["color"]
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	mi.material_override = mat
	add_child(mi)
	# A soft light so it's findable at night with the lantern off.
	var lamp := OmniLight3D.new()
	lamp.light_color = col
	lamp.light_energy = 2.0
	lamp.omni_range = 8.0
	add_child(lamp)
	# A tall translucent beacon — upgrades are rare and the maps are big, so you
	# need to be able to spot one from across the island.
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 0.35
	col_mesh.bottom_radius = 0.35
	col_mesh.height = beacon_height
	col_mesh.radial_segments = 10
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(col.r, col.g, col.b, 0.22)
	beam_mat.emission_enabled = true
	beam_mat.emission = col
	beam_mat.emission_energy_multiplier = 2.0
	var beacon := MeshInstance3D.new()
	beacon.mesh = col_mesh
	beacon.material_override = beam_mat
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.position.y = beacon_height * 0.5
	add_child(beacon)

func _snap_to_ground() -> void:
	await get_tree().process_frame
	var ground := get_tree().get_first_node_in_group("island")
	if ground and ground.has_method("height_at"):
		global_position.y = ground.height_at(global_position.x, global_position.z) + rest_height
	_base_y = global_position.y

func _process(delta: float) -> void:
	_time += delta
	rotate_y(spin_speed * delta)
	global_position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	# Driving counts — you can grab an upgrade by running it over.
	if not (body.is_in_group("player") or (body.is_in_group("vehicle") and Game.driving)):
		return
	if not Game.has_gun:
		return                                # nothing to upgrade yet — leave it
	Fx.poof(global_position, _look()["color"], 18, 0.9)
	Sfx.exotic()
	Game.set_weapon_mode(kind)
	collected.emit(kind)
	queue_free()
