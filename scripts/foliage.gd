class_name Foliage
extends RefCounted
# Swaps a mesh's materials for the wind shader, keeping whatever albedo colour or
# texture they already had. Used by both levels' foliage; rocks are deliberately
# left alone (they're built the same way, but boulders shouldn't breathe).
#
# Wrapping the EXISTING materials matters: a material_override on the
# MultiMeshInstance would replace every surface at once and flatten a tree's
# trunk and canopy to a single colour.

const SHADER := preload("res://assets/materials/foliage_sway.gdshader")


static func sway_material(source: Material, strength: float, height: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("sway_strength", strength)
	m.set_shader_parameter("sway_height", height)
	if source is BaseMaterial3D:
		var b := source as BaseMaterial3D
		m.set_shader_parameter("albedo_color", b.albedo_color)
		m.set_shader_parameter("roughness_value", b.roughness)
		if b.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
			m.set_shader_parameter("use_texture", true)
	return m


# Give every surface of `mesh` the wind shader. `height` is the local Y at which
# the sway reaches full strength — roughly the plant's own height, so a grass
# tuft and a 20 m tree both bend from the right place.
static func apply_sway(mesh: Mesh, strength: float, height: float) -> void:
	if mesh == null or not (mesh is ArrayMesh):
		return
	var am := mesh as ArrayMesh
	for i in am.get_surface_count():
		am.surface_set_material(i, sway_material(am.surface_get_material(i), strength, height))
