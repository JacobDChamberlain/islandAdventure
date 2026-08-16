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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # so winding never hides the surface

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
