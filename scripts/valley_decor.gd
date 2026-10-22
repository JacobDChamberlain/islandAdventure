extends Node3D
# Everything that stands ON Sky Valley's ground: the village, the small city,
# the mushroom forest, the monoliths, the floating islands and their stepping
# stones up to the Sky Temple, and the trees. valley.gd adds this once the
# ground exists, so everything here can sit on height_at().
#
# Routes are deliberate, not scattered: the monolith spire's spiral stair
# leads to the first sky island, and stepping stones chain each island to the
# next, climbing all the way to the Sky Temple — whose light beam is visible
# from anywhere in the valley, so there's always somewhere to head for.

var valley: Node3D   # set by valley.gd before add_child

const V := preload("res://scripts/valley.gd")

var _rng := RandomNumberGenerator.new()
var _lamps: Array = []          # {kind, pos, yaw} — read by lamps.gd via valley.lamp_spots()
var _bobbers: Array = []        # [node, base_y, phase, amount] gently floating things
var _t := 0.0
var _mats := {}

# The floating-island route, lowest to highest. The first entry is the top of
# the monolith spire (built in _build_monoliths); the last is the Sky Temple.
const SKY_CHAIN: Array[Dictionary] = [
	{"pos": Vector2(-110, -205), "top": 104.0, "r": 16.0},
	{"pos": Vector2(-40, -175), "top": 120.0, "r": 20.0},
	{"pos": Vector2(35, -215), "top": 136.0, "r": 24.0},
	{"pos": Vector2(110, -175), "top": 150.0, "r": 16.0},
	{"pos": Vector2(140, -105), "top": 165.0, "r": 14.0},
	{"pos": Vector2(80, -40), "top": 185.0, "r": 30.0, "temple": true},
]
# Lone islands to fly to, around the valley.
const SKY_LONE: Array[Dictionary] = [
	{"pos": Vector2(0, 40), "top": 60.0, "r": 14.0},
	{"pos": Vector2(-70, 110), "top": 75.0, "r": 12.0},
	{"pos": Vector2(170, -20), "top": 90.0, "r": 12.0},
	{"pos": Vector2(-200, -30), "top": 70.0, "r": 10.0},
	{"pos": Vector2(110, 285), "top": 55.0, "r": 10.0},
]
const SPIRE := Vector2(-172, -252)
const SPIRE_H := 42.0

func _ready() -> void:
	_rng.seed = 90210
	_build_village()
	_build_town()
	_build_mushrooms()
	_build_monoliths()
	_build_sky()
	_build_foliage()
	_flush_batches()

func lamp_spots() -> Array:
	return _lamps

func _process(delta: float) -> void:
	_t += delta
	for b in _bobbers:
		var n: Node3D = b[0]
		n.position.y = b[1] + sin(_t * 0.9 + b[2]) * b[3]

# --- Helpers ------------------------------------------------------------------------

func _mat(c: Color, emit: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c, emit, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

# Static decoration is BATCHED: every piece sharing a material (and a 160 m
# tile of the map, so culling still works) is merged into one mesh at the end
# of _ready. Hundreds of glyph strips and mushroom spots would otherwise be
# hundreds of draw calls. Pass keep_node for things that move.
const BATCH_TILE := 160.0
var _batches := {}   # key -> {st: SurfaceTool, mat: Material, shadows: bool}

func _mesh(prim: Mesh, mat: Material, xf: Transform3D, shadows: bool = true, keep_node: bool = false) -> MeshInstance3D:
	if keep_node:
		var mi := MeshInstance3D.new()
		mi.mesh = prim
		mi.material_override = mat
		mi.transform = xf
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		return mi
	var tile := Vector2i(floori(xf.origin.x / BATCH_TILE), floori(xf.origin.z / BATCH_TILE))
	for surf in prim.get_surface_count():
		var m: Material = mat if mat != null else prim.surface_get_material(surf)
		var key := "%d|%s|%s|%s" % [m.get_instance_id() if m else 0, tile, shadows, xf.origin.y > 150.0]
		if not _batches.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batches[key] = {"st": st, "mat": m, "shadows": shadows}
		(_batches[key]["st"] as SurfaceTool).append_from(prim, surf, xf)
	return null

func _flush_batches() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var mesh: ArrayMesh = (b["st"] as SurfaceTool).commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = b["mat"]
		if not b["shadows"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batches.clear()

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _cyl(top: float, bottom: float, h: float, segs: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

# A solid box you can stand on (mesh + matching collider), transform at its centre.
func _solid_box(size: Vector3, mat: Material, xf: Transform3D) -> void:
	_mesh(_box(size), mat, xf)
	var body := StaticBody3D.new()
	body.transform = xf
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

func _solid_cyl(r: float, h: float, mat: Material, xf: Transform3D, segs: int = 12) -> void:
	_mesh(_cyl(r, r, h, segs), mat, xf)
	var body := StaticBody3D.new()
	body.transform = xf
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

func _ground(x: float, z: float) -> float:
	return valley.height_at(x, z)

func _glb_mesh(path: String) -> Mesh:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate()
	var out: Mesh = null
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		out = (c as MeshInstance3D).mesh
		break
	inst.free()
	return out

func _label(text: String, at: Vector3, size: int = 64, color: Color = Color(1, 0.95, 0.8)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 14
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = at
	add_child(l)
	return l

# --- The village ---------------------------------------------------------------------
# Round huts with cone roofs around a dirt square, a well, a dock out into the
# sea and a footbridge over the river — Sandover-style. Lanterns light it at night.

func _build_village() -> void:
	var c: Vector2 = V.VILLAGE
	var huts := [
		[Vector2(-42, 16), 6.0, Color(0.85, 0.78, 0.62), Color(0.25, 0.42, 0.75)],   # the Elder's
		[Vector2(-32, -16), 4.2, Color(0.82, 0.72, 0.55), Color(0.80, 0.62, 0.28)],
		[Vector2(-14, 36), 4.0, Color(0.78, 0.66, 0.50), Color(0.72, 0.52, 0.25)],
		[Vector2(16, 34), 4.4, Color(0.88, 0.80, 0.66), Color(0.65, 0.30, 0.22)],
		[Vector2(-18, -40), 3.8, Color(0.80, 0.70, 0.56), Color(0.80, 0.62, 0.28)],
		[Vector2(22, -32), 4.2, Color(0.86, 0.76, 0.60), Color(0.35, 0.55, 0.35)],
		[Vector2(-56, -4), 3.6, Color(0.78, 0.68, 0.52), Color(0.72, 0.52, 0.25)],
	]
	for h in huts:
		var p: Vector2 = c + h[0]
		_hut(p, h[1], h[2], h[3], c)
	# The well.
	var wp := c + Vector2(8, 6)
	var wy := _ground(wp.x, wp.y)
	var stone := _mat(Color(0.55, 0.53, 0.5))
	var wood := _mat(Color(0.45, 0.30, 0.18))
	_solid_cyl(1.6, 1.0, stone, Transform3D(Basis(), Vector3(wp.x, wy + 0.5, wp.y)), 14)
	_mesh(_cyl(1.25, 1.25, 0.1, 14), _mat(Color(0.12, 0.3, 0.45), 0.0, 0.1), Transform3D(Basis(), Vector3(wp.x, wy + 0.85, wp.y)))
	for sx in [-1.3, 1.3]:
		_mesh(_box(Vector3(0.2, 2.4, 0.2)), wood, Transform3D(Basis(), Vector3(wp.x + sx, wy + 2.0, wp.y)))
	_mesh(_cyl(0.0, 2.2, 1.0, 4), _mat(Color(0.65, 0.30, 0.22)), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(wp.x, wy + 3.6, wp.y)))
	# Lanterns ringing the square.
	for k in 6:
		var a := k * TAU / 6.0 + 0.3
		var lp := c + Vector2(cos(a), sin(a)) * 19.0
		_lamps.append({"kind": "lantern", "pos": Vector3(lp.x, _ground(lp.x, lp.y), lp.y), "yaw": a + PI})
	_build_dock(c, wood)
	_build_bridge(c, wood)
	# Welcome sign by the square.
	var sp := c + Vector2(-6, 16)
	var sy := _ground(sp.x, sp.y)
	_mesh(_box(Vector3(0.25, 2.6, 0.25)), wood, Transform3D(Basis(), Vector3(sp.x, sy + 1.3, sp.y)))
	_mesh(_box(Vector3(3.4, 1.4, 0.15)), _mat(Color(0.6, 0.42, 0.25)), Transform3D(Basis(), Vector3(sp.x, sy + 2.4, sp.y)))
	_label("SKY VALLEY\njump again in mid-air to FLY\n(or press V)", Vector3(sp.x, sy + 4.2, sp.y), 56)

func _hut(p: Vector2, r: float, wall: Color, roof: Color, face: Vector2) -> void:
	var gy := _ground(p.x, p.y) - 0.3
	var wall_h := 3.6
	var wm := _mat(wall)
	_solid_cyl(r, wall_h, wm, Transform3D(Basis(), Vector3(p.x, gy + wall_h * 0.5, p.y)), 14)
	var roof_mesh := _cyl(0.0, r * 1.3, r * 0.95, 14)
	var rxf := Transform3D(Basis(), Vector3(p.x, gy + wall_h + r * 0.95 * 0.5, p.y))
	_mesh(roof_mesh, _mat(roof), rxf)
	var rb := StaticBody3D.new()
	rb.transform = rxf
	var rcs := CollisionShape3D.new()
	rcs.shape = roof_mesh.create_convex_shape()
	rb.add_child(rcs)
	add_child(rb)
	# Door and two warm windows on the side facing the square.
	var to := (face - p).normalized()
	var yaw := atan2(to.x, to.y)
	var basis := Basis(Vector3.UP, yaw)
	var out := Vector3(to.x, 0, to.y)
	_mesh(_box(Vector3(1.3, 2.2, 0.3)), _mat(Color(0.32, 0.2, 0.12)),
		Transform3D(basis, Vector3(p.x, gy + 1.1, p.y) + out * (r - 0.05)))
	var side := Vector3(out.z, 0, -out.x)
	for s in [-1.0, 1.0]:
		var wpos: Vector3 = Vector3(p.x, gy + 2.2, p.y) + out * (r * 0.92) + side * s * r * 0.45
		_mesh(_box(Vector3(0.8, 0.7, 0.3)), _mat(Color(1.0, 0.75, 0.4), 0.9), Transform3D(Basis(Vector3.UP, yaw + s * 0.45), wpos))

func _build_dock(c: Vector2, wood: Material) -> void:
	# Walk south from the square until the ground meets the sea.
	var x := c.x - 8.0
	var z := c.y + 40.0
	while z < c.y + 200.0 and _ground(x, z) > 0.8:
		z += 2.0
	var start := z - 8.0
	var length := 36.0
	var deck_y := maxf(_ground(x, start) + 0.4, 1.6)
	_solid_box(Vector3(4.5, 0.4, length), wood, Transform3D(Basis(), Vector3(x, deck_y, start + length * 0.5)))
	for k in 7:
		for sx in [-2.0, 2.0]:
			var pz := start + 3.0 + k * 5.5
			_mesh(_cyl(0.22, 0.22, 7.0, 6), wood, Transform3D(Basis(), Vector3(x + sx, deck_y - 3.4, pz)))
	_lamps.append({"kind": "lantern", "pos": Vector3(x + 2.6, deck_y, start + length - 2.0), "yaw": 0.0})

func _build_bridge(c: Vector2, wood: Material) -> void:
	# The river point nearest the village's east side, spanned crosswise.
	var pts: PackedVector2Array = valley.river_points()
	var target := c + Vector2(48, -15)
	var best := 0
	for k in pts.size():
		if pts[k].distance_to(target) < pts[best].distance_to(target):
			best = k
	var p := pts[best]
	var dir := (pts[mini(best + 1, pts.size() - 1)] - pts[maxi(best - 1, 0)]).normalized()
	var across := Vector2(-dir.y, dir.x)
	var half: float = valley.river_half_width + valley.river_bank + 2.0
	var e1 := p + across * half
	var e2 := p - across * half
	var deck_y := maxf(_ground(e1.x, e1.y), _ground(e2.x, e2.y)) + 0.3
	var yaw := atan2(across.x, across.y)
	var basis := Basis(Vector3.UP, yaw)
	var mid := Vector3(p.x, deck_y, p.y)
	_solid_box(Vector3(4.5, 0.45, half * 2.0), wood, Transform3D(basis, mid))
	for s in [-1.0, 1.0]:
		var off := basis * Vector3(s * 2.1, 0.9, 0)
		_solid_box(Vector3(0.18, 0.9, half * 2.0), wood, Transform3D(basis, mid + off))
	for e in [e1, e2]:
		_lamps.append({"kind": "lantern", "pos": Vector3(e.x, _ground(e.x, e.y), e.y) + basis * Vector3(3.2, 0, 0), "yaw": yaw})

# --- The small city ------------------------------------------------------------------
# A 3x3 grid of blocks: eight buildings round a plaza with a fountain, street
# lamps at every crossing. The same Meshy buildings as the big city, kept at
# their own proportions.

func _build_town() -> void:
	var models: Array = []
	var shapes: Array = []
	for i in range(1, 6):
		var m := _glb_mesh("res://assets/models/city_building_%d.glb" % i)
		if m:
			models.append(m)
			shapes.append(m.create_trimesh_shape())
	var c: Vector2 = V.TOWN
	var pitch: float = V.TOWN_PITCH
	var k := 0
	for bx in [-1, 0, 1]:
		for bz in [-1, 0, 1]:
			var bc := c + Vector2(bx * pitch, bz * pitch)
			var gy := _ground(bc.x, bc.y)
			if bx == 0 and bz == 0:
				_fountain(bc, gy)
				continue
			if models.is_empty():
				continue
			var mi_idx := (k * 3 + 1) % models.size()
			k += 1
			var mesh: Mesh = models[mi_idx]
			var box := mesh.get_aabb()
			var foot := pitch - 10.0 - 6.0
			var s := minf(foot / maxf(box.size.x, box.size.z), 55.0 / box.size.y)
			var yaw := float((k * 7) % 4) * PI * 0.5
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
			var centre := Vector3((box.position.x + box.size.x * 0.5), box.position.y, (box.position.z + box.size.z * 0.5))
			var origin := Vector3(bc.x, gy, bc.y) - basis * centre
			var xf := Transform3D(basis, origin)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.transform = xf
			add_child(mi)
			var body := StaticBody3D.new()
			body.transform = xf
			var cs := CollisionShape3D.new()
			cs.shape = shapes[mi_idx]
			body.add_child(cs)
			add_child(body)
	# Street lamps on a corner of every crossing.
	for ox in [-72.0, -24.0, 24.0, 72.0]:
		for oz in [-72.0, -24.0, 24.0, 72.0]:
			var lp := c + Vector2(ox + 6.5, oz + 6.5)
			_lamps.append({"kind": "street", "pos": Vector3(lp.x, _ground(lp.x, lp.y), lp.y), "yaw": atan2(1.0, -1.0)})

func _fountain(c: Vector2, gy: float) -> void:
	var stone := _mat(Color(0.7, 0.68, 0.64))
	_solid_cyl(7.0, 1.0, stone, Transform3D(Basis(), Vector3(c.x, gy + 0.5, c.y)), 24)
	_mesh(_cyl(6.4, 6.4, 0.1, 24), _mat(Color(0.2, 0.5, 0.7), 0.0, 0.05), Transform3D(Basis(), Vector3(c.x, gy + 1.02, c.y)))
	_solid_cyl(0.8, 4.0, stone, Transform3D(Basis(), Vector3(c.x, gy + 2.5, c.y)), 12)
	_mesh(_cyl(2.2, 0.6, 0.6, 16), stone, Transform3D(Basis(), Vector3(c.x, gy + 4.6, c.y)))
	var spray: GPUParticles3D = valley.make_mist(Vector3(c.x, gy + 5.0, c.y), Vector3(0.3, 0.1, 0.3),
		Color(0.85, 0.95, 1.0, 0.6), 0.5, 60, 1.4, 6.0)
	(spray.process_material as ParticleProcessMaterial).gravity = Vector3(0, -9.8, 0)
	(spray.process_material as ParticleProcessMaterial).spread = 25.0
	add_child(spray)

# --- The glowing mushroom forest ---------------------------------------------------------
# Giant mushrooms whose caps glow (and bounce you sky-high — the cap colliders
# carry a "bounce" meta that player.gd honours), little glowing ones in the
# moss, and spores drifting up through it all.

const SHROOM_COLORS: Array[Color] = [
	Color(0.25, 0.9, 1.0), Color(1.0, 0.35, 0.85), Color(0.65, 0.45, 1.0), Color(0.6, 1.0, 0.35),
]

func _build_mushrooms() -> void:
	var c: Vector2 = V.SHROOMS
	var placed: Array = []
	var stem_mat := _mat(Color(0.86, 0.83, 0.74), 0.15)
	var dot_mat := _mat(Color(1, 1, 1), 1.5)
	var lights := 0
	var tries := 600
	while placed.size() < 42 and tries > 0:
		tries -= 1
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 112.0
		var p := c + Vector2(cos(a), sin(a)) * r
		var h := lerpf(5.0, 24.0, pow(_rng.randf(), 1.8))
		var cap_r := h * 0.32 + 1.5
		if valley.river_distance(p.x, p.y) < 22.0 or _near_lava(p, 14.0):
			continue
		var ok := true
		for q in placed:
			if p.distance_to(q[0]) < cap_r + q[1] + 2.0:
				ok = false
				break
		if not ok:
			continue
		placed.append([p, cap_r])
		var gy := _ground(p.x, p.y) - 0.3
		var col: Color = SHROOM_COLORS[_rng.randi() % SHROOM_COLORS.size()]
		var stem_r := 0.07 * h + 0.35
		_solid_cyl(stem_r, h, stem_mat, Transform3D(Basis(), Vector3(p.x, gy + h * 0.5, p.y)), 10)
		var cap := SphereMesh.new()
		cap.radius = cap_r
		cap.height = cap_r * 0.75
		cap.is_hemisphere = true
		cap.radial_segments = 20
		cap.rings = 6
		var top := gy + h
		_mesh(cap, _mat(col * 0.75, 1.1), Transform3D(Basis(), Vector3(p.x, top, p.y)))
		_mesh(_cyl(cap_r * 0.98, cap_r * 0.98, 0.25, 20), _mat(col.lightened(0.4), 0.6),
			Transform3D(Basis(), Vector3(p.x, top - 0.1, p.y)), false)
		# Spots.
		for d in _rng.randi_range(3, 6):
			var da := _rng.randf() * TAU
			var dr := _rng.randf_range(0.2, 0.7) * cap_r
			var dot := SphereMesh.new()
			dot.radius = cap_r * 0.09
			dot.height = cap_r * 0.18
			dot.radial_segments = 8
			dot.rings = 4
			var dy := sqrt(maxf(cap_r * cap_r - dr * dr, 0.0)) * 0.75
			_mesh(dot, dot_mat, Transform3D(Basis(), Vector3(p.x + cos(da) * dr, top + dy, p.y + sin(da) * dr)), false)
		# Bouncy cap.
		var body := StaticBody3D.new()
		body.position = Vector3(p.x, top + cap_r * 0.75 - 0.3, p.y)
		body.set_meta("bounce", minf(20.0 + h * 0.6, 36.0))
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = cap_r * 0.8
		shape.height = 0.6
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		# Only the biggest few get a real light (each costs GPU time); the caps
		# glow on their own regardless.
		if h > 16.0 and lights < 6:
			lights += 1
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 2.0
			l.omni_range = cap_r * 2.0 + 8.0
			l.position = Vector3(p.x, top - 1.5, p.y)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 80.0
			l.distance_fade_length = 20.0
			add_child(l)
	_small_mushrooms(c)
	var spores: GPUParticles3D = valley.make_mist(Vector3(c.x, _ground(c.x, c.y) + 3.0, c.y),
		Vector3(105, 4, 105), Color(0.7, 0.95, 1.0, 0.95), 0.18, 700, 9.0, 0.8)
	var sm := spores.draw_pass_1.surface_get_material(0) as StandardMaterial3D
	if sm == null:
		sm = (spores.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	if sm:
		sm.emission_enabled = true
		sm.emission = Color(0.5, 0.9, 1.0)
		sm.emission_energy_multiplier = 3.0
	add_child(spores)

func _near_lava(p: Vector2, margin: float) -> bool:
	for a in 8:
		var q := p + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * margin
		if valley.lava_surface_at(q.x, q.y) > -INF:
			return true
	return valley.lava_surface_at(p.x, p.y) > -INF

func _small_mushrooms(c: Vector2) -> void:
	for col in SHROOM_COLORS:
		var mesh := ArrayMesh.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(_cyl(0.06, 0.08, 0.5, 6), 0, Transform3D(Basis(), Vector3(0, 0.25, 0)))
		st.set_material(_mat(Color(0.9, 0.88, 0.8), 0.3))
		st.commit(mesh)
		var cap := SphereMesh.new()
		cap.radius = 0.3
		cap.height = 0.22
		cap.is_hemisphere = true
		cap.radial_segments = 8
		cap.rings = 3
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		st2.append_from(cap, 0, Transform3D(Basis(), Vector3(0, 0.5, 0)))
		st2.set_material(_mat(col, 2.2))
		st2.commit(mesh)
		var xfs: Array[Transform3D] = []
		for n in 110:
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * 118.0
			var p := c + Vector2(cos(a), sin(a)) * r
			if valley.river_distance(p.x, p.y) < 10.0 or valley.lava_surface_at(p.x, p.y) > -INF:
				continue
			var s := _rng.randf_range(0.7, 2.2)
			xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(p.x, _ground(p.x, p.y) - 0.05, p.y)))
		_multimesh(mesh, xfs, false, 140.0)

# Instances are split into map tiles, one MultiMesh each: a single MultiMesh
# spanning the whole valley can't be culled, so every tuft of grass on the far
# side of the map got drawn. `draw_dist` > 0 also stops drawing a tile that far
# from the camera (with a fade), which is what keeps grass and bushes cheap.
func _multimesh(mesh: Mesh, xfs: Array[Transform3D], shadows: bool = true, draw_dist: float = 0.0, tile: float = 100.0) -> void:
	if xfs.is_empty():
		return
	var buckets := {}
	for xf in xfs:
		var key := Vector2i(floori(xf.origin.x / tile), floori(xf.origin.z / tile))
		if not buckets.has(key):
			buckets[key] = [] as Array[Transform3D]
		buckets[key].append(xf)
	for key in buckets:
		var list: Array[Transform3D] = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if draw_dist > 0.0:
			mmi.visibility_range_end = draw_dist
			mmi.visibility_range_end_margin = draw_dist * 0.15
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)

# --- The monoliths ---------------------------------------------------------------------
# Up on the plateau in the mountains: a henge of glyph-lit slabs round a dais
# with a floating orb, more slabs jutting from the slopes at odd angles, and one
# great spire with a stair spiralling up it to the first floating island.

func _build_monoliths() -> void:
	var c: Vector2 = V.MONOLITHS
	var stone := _mat(Color(0.13, 0.13, 0.16), 0.0, 0.6)
	var glyph := _mat(Color(0.25, 0.9, 1.0), 2.6)
	# The henge.
	for k in 10:
		var a := k * TAU / 10.0
		var p := c + Vector2(cos(a), sin(a)) * 30.0
		var h := _rng.randf_range(16.0, 26.0)
		var tilt := Basis(Vector3.RIGHT, _rng.randf_range(-0.08, 0.08)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.06, 0.06))
		var basis := Basis(Vector3.UP, atan2(-cos(a), -sin(a))) * tilt
		_monolith(p, Vector3(5.0, h, 2.4), basis, stone, glyph, 1.0)
	# The dais and its orb.
	var gy := _ground(c.x, c.y)
	_solid_cyl(9.0, 1.2, stone, Transform3D(Basis(), Vector3(c.x, gy + 0.3, c.y)), 32)
	_mesh(_cyl(7.0, 7.0, 0.05, 32), glyph, Transform3D(Basis(), Vector3(c.x, gy + 0.93, c.y)), false)
	_solid_cyl(6.2, 1.2, stone, Transform3D(Basis(), Vector3(c.x, gy + 1.0, c.y)), 32)
	var orb := SphereMesh.new()
	orb.radius = 1.8
	orb.height = 3.6
	orb.radial_segments = 24
	orb.rings = 12
	var orb_mi := _mesh(orb, glyph, Transform3D(Basis(), Vector3(c.x, gy + 6.0, c.y)), false, true)
	_bobbers.append([orb_mi, gy + 6.0, 0.0, 0.6])
	var ol := OmniLight3D.new()
	ol.light_color = Color(0.3, 0.9, 1.0)
	ol.light_energy = 3.0
	ol.omni_range = 26.0
	ol.position = Vector3(c.x, gy + 6.0, c.y)
	add_child(ol)
	# Slabs jutting out of the slopes around the plateau, some leaning hard.
	var made := 0
	var tries := 200
	while made < 14 and tries > 0:
		tries -= 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(48.0, 150.0)
		var p := c + Vector2(cos(a), sin(a)) * r
		if p.distance_to(SPIRE) < 18.0 or absf(p.x) > 360.0 or p.y < -380.0:
			continue
		var h := _rng.randf_range(18.0, 46.0)
		var lean := _rng.randf_range(0.05, 0.55)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, lean)
		_monolith(p, Vector3(_rng.randf_range(4.0, 8.0), h, _rng.randf_range(2.0, 4.0)), basis, stone, glyph, 0.35)
		made += 1
	_build_spire(stone, glyph)

# One slab, stood on the ground (sunk a little), with glowing glyph strips.
func _monolith(p: Vector2, size: Vector3, basis: Basis, stone: Material, glyph: Material, sink_frac: float) -> void:
	var gy := _ground(p.x, p.y)
	var sink := 2.0 + size.y * 0.25 * (1.0 - sink_frac)
	var centre := Vector3(p.x, gy - sink, p.y) + basis * Vector3(0, size.y * 0.5, 0)
	var xf := Transform3D(basis, centre)
	_solid_box(size, stone, xf)
	# Glyph strips down both faces, and a band near the top.
	for face in [-1.0, 1.0]:
		for s in [-0.25, 0.25]:
			var g_xf := xf * Transform3D(Basis(), Vector3(size.x * s, size.y * 0.05, face * (size.z * 0.5 + 0.03)))
			_mesh(_box(Vector3(0.28, size.y * 0.55, 0.06)), glyph, g_xf, false)
		var band := xf * Transform3D(Basis(), Vector3(0, size.y * 0.38, face * (size.z * 0.5 + 0.03)))
		_mesh(_box(Vector3(size.x * 0.8, 0.3, 0.06)), glyph, band, false)

# The spire: a tall square column with a stair of floating blocks spiralling up
# it. From its top, stepping stones lead to the first sky island.
func _build_spire(stone: Material, glyph: Material) -> void:
	var gy := _ground(SPIRE.x, SPIRE.y)
	_solid_box(Vector3(8, SPIRE_H, 8), stone, Transform3D(Basis(), Vector3(SPIRE.x, gy + SPIRE_H * 0.5, SPIRE.y)))
	for band in 5:
		var by := gy + 6.0 + band * 8.0
		_mesh(_box(Vector3(8.12, 0.35, 8.12)), glyph, Transform3D(Basis(), Vector3(SPIRE.x, by, SPIRE.y)), false)
	var step_mat := _mat(Color(0.2, 0.2, 0.24), 0.0, 0.6)
	var steps := 28
	for k in steps:
		var a := k * 0.42
		var y := gy + 1.4 + k * (SPIRE_H - 1.0) / steps
		var p := Vector3(SPIRE.x + cos(a) * 6.8, y, SPIRE.y + sin(a) * 6.8)
		_solid_box(Vector3(3.6, 0.6, 2.6), step_mat, Transform3D(Basis(Vector3.UP, -a), p))
		if k % 4 == 0:
			_mesh(_box(Vector3(3.62, 0.08, 0.3)), glyph, Transform3D(Basis(Vector3.UP, -a), p + Vector3(0, 0.32, 0)), false)
	# A ring of glyph light around the top.
	_mesh(_cyl(5.0, 5.0, 0.06, 24), glyph, Transform3D(Basis(), Vector3(SPIRE.x, gy + SPIRE_H + 0.04, SPIRE.y)), false)

func spire_top() -> Vector3:
	return Vector3(SPIRE.x, _ground(SPIRE.x, SPIRE.y) + SPIRE_H, SPIRE.y)

# --- The sky -------------------------------------------------------------------------------

func _build_sky() -> void:
	var stone_mesh := _island_mesh(1.9, 7)
	var stone_xfs: Array[Transform3D] = []
	var prev_pos := spire_top()
	var prev_r := 4.0
	for i in SKY_CHAIN.size():
		var isl: Dictionary = SKY_CHAIN[i]
		var p: Vector2 = isl["pos"]
		var top: float = isl["top"]
		var r: float = isl["r"]
		_sky_island(Vector3(p.x, top, p.y), r, isl.get("temple", false))
		_stepping_stones(prev_pos, prev_r, Vector3(p.x, top, p.y), r, stone_xfs)
		prev_pos = Vector3(p.x, top, p.y)
		prev_r = r
	for isl in SKY_LONE:
		var p: Vector2 = isl["pos"]
		_sky_island(Vector3(p.x, isl["top"], p.y), isl["r"], false)
	_multimesh(stone_mesh, stone_xfs)
	var col := CylinderShape3D.new()
	col.radius = 1.8
	col.height = 0.8
	for xf in stone_xfs:
		var body := StaticBody3D.new()
		body.transform = Transform3D(Basis(), xf.origin + Vector3(0, -0.2, 0))
		var cs := CollisionShape3D.new()
		cs.shape = col
		body.add_child(cs)
		add_child(body)

# Stones from the edge of one island to the next, about 5 m apart and never
# more than a comfortable hop higher, weaving a little so it reads as a path.
func _stepping_stones(a: Vector3, ra: float, b: Vector3, rb: float, out: Array[Transform3D]) -> void:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var dir := flat.normalized()
	var start := Vector2(a.x, a.z) + dir * (ra - 1.0)
	var end := Vector2(b.x, b.z) - dir * (rb - 1.0)
	var gap := start.distance_to(end)
	var n := maxi(1, int(ceil(gap / 5.0)) - 1)
	var perp := Vector2(-dir.y, dir.x)
	for k in range(1, n + 1):
		var t := float(k) / (n + 1)
		var q := start.lerp(end, t) + perp * sin(t * PI * 2.0) * 3.0
		var y := lerpf(a.y, b.y, t) - 0.3
		out.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(q.x, y, q.y)))

# A floating island: a grassy, slightly domed top over a jagged rock cone.
func _sky_island(at: Vector3, r: float, temple: bool) -> void:
	var mesh := _island_mesh(r, _rng.randi())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	add_child(mi)
	var body := StaticBody3D.new()
	body.position = at
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
	# Crystals hanging off the bottom.
	var crystal := _mat(Color(0.5, 0.85, 1.0), 2.0)
	for k in 3:
		var a := _rng.randf() * TAU
		_mesh(_cyl(0.0, 0.6, 3.0, 5), crystal,
			Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.8)),
				at + Vector3(cos(a) * r * 0.25, -r * 0.9, sin(a) * r * 0.25)), false)
	if temple:
		_sky_temple(at, r)
		return
	# A few trees and rocks on top.
	var tree := _make_tree()
	for k in int(r / 4.0):
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * r * 0.6
		var s := _rng.randf_range(1.2, 2.4)
		_mesh(tree, null, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s),
			at + Vector3(cos(a) * d, 0.5, sin(a) * d)))

func _sky_temple(at: Vector3, r: float) -> void:
	var marble := _mat(Color(0.92, 0.9, 0.86), 0.0, 0.5)
	var gold := _mat(Color(1.0, 0.8, 0.35), 2.0, 0.3)
	_solid_cyl(18.0, 1.2, marble, Transform3D(Basis(), at + Vector3(0, 0.9, 0)), 40)
	_mesh(_cyl(18.05, 18.05, 0.25, 40), gold, Transform3D(Basis(), at + Vector3(0, 1.35, 0)), false)
	for k in 8:
		var a := k * TAU / 8.0
		var pp := at + Vector3(cos(a) * 14.5, 0, sin(a) * 14.5)
		_solid_cyl(0.9, 14.0, marble, Transform3D(Basis(), pp + Vector3(0, 8.5, 0)), 12)
		_mesh(_cyl(0.95, 0.95, 0.5, 12), gold, Transform3D(Basis(), pp + Vector3(0, 13.0, 0)), false)
		_mesh(_box(Vector3(2.4, 0.8, 2.4)), marble, Transform3D(Basis(), pp + Vector3(0, 15.8, 0)))
	_solid_cyl(3.0, 2.0, marble, Transform3D(Basis(), at + Vector3(0, 2.5, 0)), 20)
	var orb := SphereMesh.new()
	orb.radius = 2.2
	orb.height = 4.4
	orb.radial_segments = 24
	orb.rings = 12
	var orb_mi := _mesh(orb, gold, Transform3D(Basis(), at + Vector3(0, 8.0, 0)), false, true)
	_bobbers.append([orb_mi, at.y + 8.0, 1.0, 0.8])
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.5)
	l.light_energy = 4.0
	l.omni_range = 40.0
	l.position = at + Vector3(0, 8.0, 0)
	add_child(l)
	# A beam of light into the sky: the landmark you can see from everywhere.
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.35)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(_cyl(1.6, 1.6, 700.0, 16), beam_mat, Transform3D(Basis(), at + Vector3(0, 360.0, 0)), false)
	_label("SKY TEMPLE", at + Vector3(0, 19.0, 0), 96, Color(1.0, 0.9, 0.6))

# Top surface, a short dirt skirt, then the rock underside tapering to a point.
func _island_mesh(r: float, seed_: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var seg := 22
	var rim: Array[Vector3] = []
	for k in seg:
		var a := k * TAU / seg
		var rr := r * rng.randf_range(0.86, 1.1)
		rim.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
	var levels := [
		[0.96, -1.3, Color(0.42, 0.30, 0.18)],
		[0.78, -r * 0.35 - 2.0, Color(0.44, 0.40, 0.36)],
		[0.45, -r * 0.8 - 3.0, Color(0.38, 0.35, 0.33)],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass := Color(0.36, 0.62, 0.28)
	var centre := Vector3(0, 0.6, 0)
	for k in seg:
		_face(st, centre, rim[(k + 1) % seg], rim[k], grass)
	var prev := rim
	var prev_col := grass
	for lv in levels:
		var ring: Array[Vector3] = []
		for k in seg:
			var j := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))
			ring.append(Vector3(prev[k].x * lv[0], lv[1], prev[k].z * lv[0]) + j)
		for k in seg:
			var a := prev[k]
			var b := prev[(k + 1) % seg]
			var c := ring[k]
			var d := ring[(k + 1) % seg]
			_face(st, a, b, c, lv[2])
			_face(st, b, d, c, lv[2])
		prev = ring
		prev_col = lv[2]
	var tip := Vector3(rng.randf_range(-1, 1), -r * 1.4 - 4.0, rng.randf_range(-1, 1))
	for k in seg:
		_face(st, prev[k], prev[(k + 1) % seg], tip, Color(0.33, 0.31, 0.3))
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	return mesh

# Flat-shaded triangle facing OUT from the island's vertical axis (or up, on top).
func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	var mid := (a + b + c) / 3.0
	var outward := Vector3(mid.x, 0, mid.z).normalized() if absf(n.y) < 0.9 else Vector3.UP
	if mid.y > 0.0:
		outward = Vector3.UP
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)

# --- Trees and plants ---------------------------------------------------------------------

func _add_part(mesh: ArrayMesh, prim: Mesh, xf: Transform3D, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(prim, 0, xf)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	st.set_material(m)
	st.commit(mesh)

func _make_tree() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_part(mesh, _cyl(0.14, 0.24, 1.6, 6), Transform3D(Basis(), Vector3(0, 0.8, 0)), Color(0.34, 0.23, 0.14))
	var green := Color(0.15, 0.41, 0.24)
	for tier in [[1.2, 1.6, 1.8], [0.92, 1.5, 2.9], [0.6, 1.4, 3.9]]:
		_add_part(mesh, _cyl(0.0, tier[0], tier[1], 7), Transform3D(Basis(), Vector3(0, tier[2], 0)), green)
	return mesh

func _make_broadleaf() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_part(mesh, _cyl(0.16, 0.26, 2.4, 6), Transform3D(Basis(), Vector3(0, 1.2, 0)), Color(0.38, 0.26, 0.16))
	var leaf := Color(0.22, 0.50, 0.22)
	for blob in [[Vector3(0, 3.0, 0), 1.5], [Vector3(0.8, 2.6, 0.3), 1.0], [Vector3(-0.7, 2.7, -0.4), 1.1], [Vector3(0.1, 3.7, 0.2), 1.0]]:
		var s := SphereMesh.new()
		s.radius = blob[1]
		s.height = blob[1] * 1.6
		s.radial_segments = 7
		s.rings = 4
		_add_part(mesh, s, Transform3D(Basis(), blob[0]), leaf)
	return mesh

func _make_bush() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var s := SphereMesh.new()
	s.radius = 0.55
	s.height = 0.8
	s.radial_segments = 6
	s.rings = 3
	_add_part(mesh, s, Transform3D(Basis(), Vector3(0, 0.35, 0)), Color(0.28, 0.46, 0.22))
	return mesh

func _make_grass() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_part(mesh, _cyl(0.0, 0.16, 0.6, 4), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.35, 0.58, 0.28))
	return mesh

func _make_rock() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var s := SphereMesh.new()
	s.radius = 0.6
	s.height = 0.9
	s.radial_segments = 5
	s.rings = 3
	_add_part(mesh, s, Transform3D(Basis().scaled(Vector3(1.3, 0.7, 1.1)), Vector3(0, 0.25, 0)), Color(0.5, 0.49, 0.47))
	return mesh

# Where trees may grow: dry, not too steep, below the tree line, and clear of
# the places that have their own look (town, village square, forest of
# mushrooms, monoliths, volcano, river channel, tunnel mouths).
func _can_grow(x: float, z: float, h: float) -> bool:
	if h < 2.5 or h > 78.0:
		return false
	var p := Vector2(x, z)
	if valley.is_in_town(x, z) or p.distance_to(V.VILLAGE) < 48.0:
		return false
	if p.distance_to(V.SHROOMS) < 125.0 or p.distance_to(V.MONOLITHS) < 70.0 or p.distance_to(V.VOLCANO) < 150.0:
		return false
	if valley.river_distance(x, z) < valley.river_half_width + valley.river_bank:
		return false
	for t in valley.tunnel_list():
		var pts: PackedVector2Array = t["pts"]
		if p.distance_to(pts[0]) < 16.0 or p.distance_to(pts[pts.size() - 1]) < 16.0:
			return false
	var gx := _ground(x + 1.5, z) - _ground(x - 1.5, z)
	var gz := _ground(x, z + 1.5) - _ground(x, z - 1.5)
	return Vector2(gx, gz).length() / 3.0 < 0.75

func _build_foliage() -> void:
	var pine := _make_tree()
	var broad := _make_broadleaf()
	var bush := _make_bush()
	var grass := _make_grass()
	var rock := _make_rock()
	# (No Meshy plant models here: at ~28K triangles each they cost more than
	# all the other trees in the valley put together.)
	Foliage.apply_sway(pine, 0.07, 3.0)
	Foliage.apply_sway(broad, 0.06, 3.5)
	Foliage.apply_sway(bush, 0.05, 0.8)
	Foliage.apply_sway(grass, 0.06, 0.5)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.35
	trunk.height = 4.0
	var rock_col := SphereShape3D.new()
	rock_col.radius = 0.6
	var ext: float = valley.extent - 20.0
	# Pines on the higher ground toward the mountains; broadleaf in the
	# lowlands, thickest along the river (the jungle).
	_scatter(pine, 650, ext, func(x, z, h): return h > 12.0 or z < -60.0, 1.0, 2.6, true, trunk, Vector3(0, 2.0, 0))
	_scatter(broad, 750, ext, func(x, z, h): return h < 40.0 and (valley.river_distance(x, z) < 90.0 or _rng.randf() < 0.45), 1.0, 2.4, true, trunk, Vector3(0, 2.0, 0))
	_scatter(bush, 1000, ext, func(x, z, h): return true, 0.6, 1.4, false, null, Vector3.ZERO, 160.0)
	_scatter(rock, 380, ext, func(x, z, h): return true, 0.6, 2.4, true, rock_col, Vector3(0, 0.3, 0), 260.0)
	_scatter(grass, 3200, ext, func(x, z, h): return true, 0.6, 1.4, false, null, Vector3.ZERO, 90.0)

func _scatter(mesh: Mesh, count: int, ext: float, want: Callable, s_min: float, s_max: float,
		shadows: bool, col: Shape3D = null, col_off: Vector3 = Vector3.ZERO, draw_dist: float = 0.0) -> void:
	var xfs: Array[Transform3D] = []
	var tries := count * 6
	while xfs.size() < count and tries > 0:
		tries -= 1
		var x := _rng.randf_range(-ext, ext)
		var z := _rng.randf_range(-ext, ext)
		var h := _ground(x, z)
		if not _can_grow(x, z, h) or not want.call(x, z, h):
			continue
		var s := _rng.randf_range(s_min, s_max)
		xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h, z)))
	_multimesh(mesh, xfs, shadows, draw_dist, 80.0 if draw_dist > 0.0 and draw_dist < 200.0 else 100.0)
	if col == null:
		return
	for xf in xfs:
		var body := StaticBody3D.new()
		body.transform = xf
		var cs := CollisionShape3D.new()
		cs.shape = col
		cs.position = col_off
		body.add_child(cs)
		add_child(body)
