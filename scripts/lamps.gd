extends Node3D
# Night lighting for whichever level we're in, built in code (no models): street
# lamps on the city's sidewalk corners, hanging lanterns on wooden posts on the
# island. main.gd adds this node and calls set_glow() from its day/night update,
# so the lamps fade on at dusk and off at dawn.
#
# Lights are cheap-ish but not free: no shadows, and each one fades out past
# `fade_begin` metres. That also matters for the web build, whose Compatibility
# renderer only lets 8 lights touch any one mesh — and the city ground is ONE
# mesh, so only nearby lamps should be live.

# Warm, but leaning orange rather than yellow: lit light multiplies the surface
# colour, and a yellow light on green grass reads distinctly GREEN.
@export var lamp_color: Color = Color(1.0, 0.7, 0.42)
@export var fade_begin: float = 55.0
@export var fade_length: float = 20.0
# --- City street lamps ---
@export var street_light_energy: float = 3.0
@export var street_light_range: float = 22.0
@export var pole_height: float = 5.6
@export var sidewalk_inset: float = 1.6     # in from the block edge, clear of the curb ramp
# --- Island lanterns ---
@export var lantern_count: int = 12
@export var lantern_light_energy: float = 2.3
@export var lantern_light_range: float = 15.0
@export var lantern_spacing: float = 16.0  # minimum distance between posts
@export var lantern_clearance: float = 5.0 # keep posts off pads, platforms, the Elder...
@export var lantern_seed: int = 4242
@export var lantern_fade_begin: float = 110.0  # only a dozen, so they can carry further than street lamps

var _lights: Array[OmniLight3D] = []
var _energies: Array[float] = []
var _glow_mat: StandardMaterial3D
var _glow: float = -1.0
# Island lanterns sway on their chains: [pivot, phase] pairs.
var _swingers: Array = []
var _t: float = 0.0

func _ready() -> void:
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = lamp_color.darkened(0.35)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = lamp_color
	_glow_mat.roughness = 0.6
	var ground := get_tree().get_first_node_in_group("island")
	if ground == null:
		return
	# A level can hand-place its lamps (Sky Valley's village and town do);
	# otherwise the city gets street lamps and the island lanterns.
	if ground.has_method("lamp_spots"):
		_build_spots(ground.lamp_spots())
	elif ground.has_method("building_top_at"):
		_build_street_lamps(ground)
	else:
		_build_island_lanterns(ground)

# Spots are {kind: "street"|"lantern", pos: Vector3 (on the ground), yaw}.
func _build_spots(spots: Array) -> void:
	var street: Array[Transform3D] = []
	var lantern: Array[Transform3D] = []
	for sp in spots:
		var xf := Transform3D(Basis(Vector3.UP, float(sp.get("yaw", 0.0))), sp["pos"])
		if sp.get("kind", "lantern") == "street":
			street.append(xf)
		else:
			lantern.append(xf)
	_street_lamps(street)
	_lantern_posts(lantern)

# 0 = daytime (unlit), 1 = full night. Only touches the lights when it changes.
func set_glow(g: float) -> void:
	g = clampf(g, 0.0, 1.0)
	if is_equal_approx(g, _glow):
		return
	_glow = g
	if _glow_mat:
		_glow_mat.emission_energy_multiplier = g * 3.0
	for i in _lights.size():
		_lights[i].visible = g > 0.01
		_lights[i].light_energy = _energies[i] * g

func _process(delta: float) -> void:
	if _swingers.is_empty():
		return
	_t += delta
	for s in _swingers:
		var pivot: Node3D = s[0]
		var ph: float = s[1]
		pivot.rotation = Vector3(sin(_t * 1.3 + ph) * 0.07, 0.0, sin(_t * 0.9 + ph * 1.7) * 0.09)

func _add_light(parent: Node3D, pos: Vector3, energy: float, rng_: float, fade: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = lamp_color
	l.light_energy = 0.0
	l.omni_range = rng_
	l.omni_attenuation = 0.7   # flatter falloff, so the far edge of the pool isn't wasted
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = fade
	l.distance_fade_length = fade_length
	l.position = pos
	l.visible = false
	parent.add_child(l)
	_lights.append(l)
	_energies.append(energy)

func _mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _add_part(mesh: ArrayMesh, prim: Mesh, xf: Transform3D, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(prim, 0, xf)
	st.set_material(mat)
	st.commit(mesh)

func _cyl(top_r: float, bottom_r: float, h: float, segs: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _multimesh(mesh: Mesh, xforms: Array[Transform3D], shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _pole_collider(xf: Transform3D, radius: float, height: float) -> void:
	var sb := StaticBody3D.new()
	sb.position = xf.origin
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	sb.add_child(cs)
	add_child(sb)

# --- City ---------------------------------------------------------------------
# One lamp per intersection, on a sidewalk corner, its arm reaching out over the
# crossing, and one more halfway down each street. The corner alternates per intersection so the streets don't read as
# a copy-pasted grid. Lamp body and bulb are two MultiMeshes (one draw each);
# only the lights and colliders are per-lamp nodes.

func _build_street_lamps(city: Node) -> void:
	var p: float = city.block_size + city.road_width
	var corner: float = city.road_width * 0.5 + sidewalk_inset
	var bodies: Array[Transform3D] = []
	var n := int(floor((city.extent - 4.0) / p))
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var sx := 1.0 if posmod(i + j, 2) == 0 else -1.0
			var sz := 1.0 if posmod(i * 3 + j, 4) < 2 else -1.0
			var x := i * p + sx * corner
			var z := j * p + sz * corner
			# Arm points diagonally back toward the middle of the crossing.
			var yaw := atan2(sz, -sx)
			bodies.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(x, city.height_at(x, z), z)))
			# Plus one halfway along each street leaving this junction (+X and
			# +Z), on alternating sides, arm out over the road. Kept out of the
			# plaza, where Spencer, Biscuit and the portals stand.
			if i < n:
				var side := 1.0 if posmod(i + j, 2) == 0 else -1.0
				var mx := (i + 0.5) * p
				var mz := j * p + side * corner
				if Vector2(mx, mz).length() > city.plaza_radius:
					bodies.append(Transform3D(Basis(Vector3.UP, side * PI * 0.5),
							Vector3(mx, city.height_at(mx, mz), mz)))
			if j < n:
				var side := 1.0 if posmod(i + j, 2) == 1 else -1.0
				var mx := i * p + side * corner
				var mz := (j + 0.5) * p
				if Vector2(mx, mz).length() > city.plaza_radius:
					bodies.append(Transform3D(Basis(Vector3.UP, 0.0 if side < 0.0 else PI),
							Vector3(mx, city.height_at(mx, mz), mz)))
	_street_lamps(bodies)

# One street lamp per transform (at its foot; the arm reaches along local +X).
func _street_lamps(bodies: Array[Transform3D]) -> void:
	if bodies.is_empty():
		return
	var arm := 1.8
	var body := _street_lamp_mesh(arm)
	var bulb := ArrayMesh.new()
	var bulb_prim := SphereMesh.new()
	bulb_prim.radius = 0.2
	bulb_prim.height = 0.26
	bulb_prim.radial_segments = 8
	bulb_prim.rings = 4
	_add_part(bulb, bulb_prim, Transform3D(Basis(), Vector3(arm, pole_height - 0.32, 0)), _glow_mat)
	for xf in bodies:
		_pole_collider(xf, 0.14, pole_height)
		_add_light(self, xf * Vector3(arm, pole_height - 0.55, 0), street_light_energy, street_light_range, fade_begin)
	_multimesh(body, bodies, true)
	_multimesh(bulb, bodies, false)

func _street_lamp_mesh(arm: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var iron := _mat(Color(0.13, 0.14, 0.16), 0.55, 0.4)
	_add_part(mesh, _cyl(0.26, 0.32, 0.5), Transform3D(Basis(), Vector3(0, 0.25, 0)), iron)      # base
	_add_part(mesh, _cyl(0.07, 0.1, pole_height), Transform3D(Basis(), Vector3(0, pole_height * 0.5, 0)), iron)
	_add_part(mesh, _box(Vector3(arm + 0.1, 0.09, 0.09)), Transform3D(Basis(), Vector3(arm * 0.5, pole_height - 0.05, 0)), iron)
	# Hood over the bulb: a flared cone, wide end down.
	_add_part(mesh, _cyl(0.1, 0.42, 0.28), Transform3D(Basis(), Vector3(arm, pole_height - 0.16, 0)), iron)
	return mesh

# --- Island -------------------------------------------------------------------
# A wooden post with a crook arm, and a lantern hanging off it on a short chain
# that sways in the breeze. Posts go on dry, gentle ground, spaced apart, and
# kept clear of anything placed in the level (pads, platforms, the Elder).

func _build_island_lanterns(island: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = lantern_seed
	var avoid: Array[Vector2] = []
	for c in get_parent().get_children():
		if c is Node3D and not (c is Light3D) and c != island and c != self \
				and not c.is_in_group("enemy"):
			avoid.append(Vector2(c.global_position.x, c.global_position.z))
	var radius: float = island.island_radius * 0.8 if "island_radius" in island else 70.0

	var placed: Array[Vector2] = []
	var posts: Array[Transform3D] = []
	var tries := lantern_count * 40
	while placed.size() < lantern_count and tries > 0:
		tries -= 1
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * radius
		var pt := Vector2(cos(ang) * rad, sin(ang) * rad)
		var h: float = island.height_at(pt.x, pt.y)
		if h < 2.0:
			continue
		var hx: float = island.height_at(pt.x + 1.5, pt.y) - island.height_at(pt.x - 1.5, pt.y)
		var hz: float = island.height_at(pt.x, pt.y + 1.5) - island.height_at(pt.x, pt.y - 1.5)
		if Vector2(hx, hz).length() / 3.0 > 0.35:
			continue
		if _too_close(pt, placed, lantern_spacing) or _too_close(pt, avoid, lantern_clearance):
			continue
		placed.append(pt)
		posts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(pt.x, h - 0.1, pt.y)))
	_lantern_posts(posts)

# A post with a hanging lantern per transform (at its foot; arm along local +X).
func _lantern_posts(posts: Array[Transform3D]) -> void:
	if posts.is_empty():
		return
	var wood := _mat(Color(0.36, 0.24, 0.14), 0.95)
	var iron := _mat(Color(0.12, 0.12, 0.13), 0.5, 0.5)
	var post := ArrayMesh.new()
	var post_h := 3.4
	var arm := 1.1
	_add_part(post, _cyl(0.1, 0.14, post_h, 6), Transform3D(Basis(), Vector3(0, post_h * 0.5, 0)), wood)
	_add_part(post, _box(Vector3(arm + 0.2, 0.12, 0.12)), Transform3D(Basis(), Vector3(arm * 0.5, post_h - 0.15, 0)), wood)
	# A diagonal brace under the arm.
	_add_part(post, _box(Vector3(0.8, 0.08, 0.08)),
			Transform3D(Basis(Vector3.BACK, deg_to_rad(40.0)), Vector3(0.3, post_h - 0.45, 0)), wood)
	for k in posts.size():
		var xf := posts[k]
		_pole_collider(xf, 0.15, post_h)
		_hang_lantern(xf * Vector3(arm, post_h - 0.21, 0), xf.basis, iron, float(k) * 1.7)
	_multimesh(post, posts, true)

func _too_close(pt: Vector2, others: Array[Vector2], dist: float) -> bool:
	for o in others:
		if pt.distance_to(o) < dist:
			return true
	return false

func _hang_lantern(at: Vector3, basis: Basis, iron: Material, phase: float) -> void:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = at
	var holder := Node3D.new()   # carries the post's yaw; the pivot only swings
	holder.basis = basis
	pivot.add_child(holder)
	var mesh := ArrayMesh.new()
	var chain := 0.35
	_add_part(mesh, _cyl(0.015, 0.015, chain, 4), Transform3D(Basis(), Vector3(0, -chain * 0.5, 0)), iron)
	var top := -chain
	_add_part(mesh, _cyl(0.05, 0.2, 0.12, 6), Transform3D(Basis(), Vector3(0, top - 0.06, 0)), iron)       # cap
	_add_part(mesh, _cyl(0.15, 0.15, 0.32, 6), Transform3D(Basis(), Vector3(0, top - 0.28, 0)), _glow_mat) # glass
	_add_part(mesh, _cyl(0.17, 0.12, 0.06, 6), Transform3D(Basis(), Vector3(0, top - 0.47, 0)), iron)      # base
	# Four corner bars over the glass, so it reads as a lantern and not a jar.
	for k in 4:
		var a := k * TAU / 4.0 + TAU / 8.0
		_add_part(mesh, _box(Vector3(0.025, 0.34, 0.025)),
				Transform3D(Basis(), Vector3(cos(a) * 0.15, top - 0.28, sin(a) * 0.15)), iron)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	_add_light(holder, Vector3(0, top - 0.28, 0), lantern_light_energy, lantern_light_range, lantern_fade_begin)
	_swingers.append([pivot, phase])
