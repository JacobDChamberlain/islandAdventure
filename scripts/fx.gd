extends Node
# Global visual-effects helper. Call Fx.poof(...) to spawn a quick one-shot
# particle burst anywhere (stomps, gem pickups, etc.). Auto-frees itself.

func poof(pos: Vector3, color: Color, amount: int = 18, power: float = 1.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 2.5 * power
	pm.initial_velocity_max = 6.0 * power
	pm.gravity = Vector3(0, -8, 0)
	pm.scale_min = 0.15 * power
	pm.scale_max = 0.4 * power
	pm.color = color

	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.radial_segments = 5
	mesh.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color.WHITE
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = dm

	var p := GPUParticles3D.new()
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.6
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true

	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(p):
		p.queue_free()
