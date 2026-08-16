extends Node3D
# Procedurally builds a large, organic, low-poly island surrounded by water.
# The shape comes from a radial falloff (high in the middle, below sea level at
# the edges) plus noise on the coastline so it's never a square or a circle.

@export var extent: float = 130.0        # half-width of the terrain mesh (spans -extent..extent)
@export var island_radius: float = 95.0  # roughly how far the land reaches from center
@export var cells: int = 100             # grid resolution (higher = smoother but slower)
@export var max_height: float = 14.0     # tallest hills
@export var coast_roughness: float = 0.35 # how wiggly/irregular the coastline is
@export var hill_amp: float = 4.0        # bumpiness of the land
@export var seabed_depth: float = 40.0   # how steeply the ground drops past the shore
@export var water_level: float = 0.4
@export var noise_seed: int = 1337

var _coast := FastNoiseLite.new()
var _hills := FastNoiseLite.new()

func _ready() -> void:
	add_to_group("island")  # so the player/gems/enemies can query height_at()
	_coast.seed = noise_seed
	_coast.frequency = 0.006
	_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_hills.seed = noise_seed + 99
	_hills.frequency = 0.03
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_build_terrain()
	_build_water()
	_build_foliage()

# World height at a given x/z. Public so nothing else has to raycast if it
# doesn't want to. Land is always y >= 0; anything y < 0 is underwater.
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var land := (1.0 - d / island_radius) + _coast.get_noise_2d(x, z) * coast_roughness
	if land > 0.0:
		var h := pow(land, 1.1) * max_height
		h += _hills.get_noise_2d(x, z) * hill_amp * clampf(land, 0.0, 1.0)
		return h
	return land * seabed_depth

func _color_for(y: float) -> Color:
	var sand := Color(0.83, 0.76, 0.52)
	var grass := Color(0.34, 0.6, 0.28)
	var forest := Color(0.26, 0.47, 0.24)
	var rock := Color(0.46, 0.45, 0.44)
	if y < 1.5:
		return sand.lerp(grass, clampf(y / 1.5, 0.0, 1.0))
	elif y < 7.0:
		return grass
	elif y < 11.0:
		return grass.lerp(forest, (y - 7.0) / 4.0)
	else:
		return forest.lerp(rock, clampf((y - 11.0) / 4.0, 0.0, 1.0))

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := extent * 2.0 / float(cells)
	for i in cells:
		var x0 := -extent + i * step
		var x1 := x0 + step
		for j in cells:
			var z0 := -extent + j * step
			var z1 := z0 + step
			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x0, height_at(x0, z1), z1)
			var c := Vector3(x1, height_at(x1, z1), z1)
			var d := Vector3(x1, height_at(x1, z0), z0)
			# Wind so the collision face normals point UP (needed for is_on_floor).
			_tri(st, a, c, b)
			_tri(st, a, d, c)
	var mesh := st.commit()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_BACK  # winding faces up, so backface culling is safe + faster

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.create_trimesh_collision()  # adds a StaticBody3D + collision matching the mesh

# Flat-shaded triangle (unique normal per face) with a height-based vertex color.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(_color_for(v.y))
		st.add_vertex(v)

func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 3.0, extent * 3.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.42, 0.62, 0.62)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.2
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, water_level, 0)
	add_child(mi)

# --- Foliage: procedural low-poly props scattered with MultiMesh (fast). ---

func _build_foliage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed * 7 + 3
	var tree := _make_tree()
	#         mesh,     count,  min_h, max_h, max_slope, s_min, s_max, y_off, rng, shadows
	_scatter(tree,         75, 1.8, 11.0, 1.3, 0.9, 1.9, 0.0, rng)        # spread-out pines
	_scatter(tree,         11, 1.8,  9.0, 1.0, 2.6, 4.0, 0.0, rng)        # a few towering giants
	_scatter(_make_bush(), 300, 1.2, 12.0, 3.0, 0.6, 1.3, 0.0, rng)
	_scatter(_make_rock(), 150, 0.6, 20.0, 6.0, 0.5, 1.9, -0.2, rng)
	_scatter(_make_grass(),1300, 1.2, 9.0, 2.5, 0.6, 1.4, 0.0, rng, false) # grass: no shadows

func _scatter(mesh: ArrayMesh, count: int, min_h: float, max_h: float,
		max_slope: float, s_min: float, s_max: float, y_off: float,
		rng: RandomNumberGenerator, cast_shadow: bool = true) -> void:
	var xforms: Array[Transform3D] = []
	var tries := count * 8
	var r := island_radius * 0.98
	while xforms.size() < count and tries > 0:
		tries -= 1
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * r   # uniform spread across the disk
		var x := cos(ang) * rad
		var z := sin(ang) * rad
		var h := height_at(x, z)
		if h < min_h or h > max_h:
			continue
		var hx := height_at(x + 1.5, z) - height_at(x - 1.5, z)
		var hz := height_at(x, z + 1.5) - height_at(x, z - 1.5)
		if Vector2(hx, hz).length() / 3.0 > max_slope:
			continue
		var s := rng.randf_range(s_min, s_max)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		xforms.append(Transform3D(b, Vector3(x, h + y_off, z)))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not cast_shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.96
	return m

# Adds a primitive (offset/scaled) as a new colored surface on `mesh`.
func _add_part(mesh: ArrayMesh, prim: Mesh, xf: Transform3D, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(prim, 0, xf)
	st.set_material(_mat(col))
	st.commit(mesh)

func _make_tree() -> ArrayMesh:
	# Tall stylized pine: a trunk with three stacked cone tiers.
	var mesh := ArrayMesh.new()
	var brown := Color(0.34, 0.23, 0.14)
	var green := Color(0.15, 0.41, 0.24)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.24
	trunk.height = 1.6
	trunk.radial_segments = 6
	trunk.rings = 1
	_add_part(mesh, trunk, Transform3D(Basis(), Vector3(0, 0.8, 0)), brown)
	_cone(mesh, 1.2, 1.6, 1.8, green)
	_cone(mesh, 0.92, 1.5, 2.9, green)
	_cone(mesh, 0.6, 1.4, 3.9, green)
	return mesh

func _cone(mesh: ArrayMesh, bottom_r: float, h: float, y: float, col: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = 7
	c.rings = 1
	_add_part(mesh, c, Transform3D(Basis(), Vector3(0, y, 0)), col)

func _make_bush() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var s := SphereMesh.new()
	s.radius = 0.55
	s.height = 0.8
	s.radial_segments = 6
	s.rings = 3
	_add_part(mesh, s, Transform3D(Basis(), Vector3(0, 0.35, 0)), Color(0.28, 0.46, 0.22))
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

func _make_grass() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.16
	c.height = 0.6
	c.radial_segments = 4
	c.rings = 1
	_add_part(mesh, c, Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.35, 0.58, 0.28))
	return mesh
