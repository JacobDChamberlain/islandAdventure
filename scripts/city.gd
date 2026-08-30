extends Node3D
# Procedural greybox CITY — the second level. A big, near-flat map cut by a
# regular street grid, with low-poly box buildings on the blocks and a few green
# park blocks. Deliberately ~10x the island's land area (see `extent`).
#
# It honors the SAME contract as island.gd: it joins group "island" and exposes
# height_at(x, z). Every existing system (player ground-snap, enemy roaming,
# artifact/exotic/coin placement, launch pads, platforms, the portal) queries
# that, so they all work here with zero changes.

@export var extent: float = 260.0        # half-width of the ground (spans -extent..extent) — ~10x island area
@export var cells: int = 160             # ground grid resolution (collision trimesh)
@export var block_size: float = 44.0     # walkable block width between roads
@export var road_width: float = 12.0     # street width
@export var base_height: float = 0.6     # nominal ground height
@export var roll_amp: float = 0.0        # flat streets (0 = dead flat) — best for driving; curbs can come later as visual detail
@export var plaza_radius: float = 34.0   # keep the center clear (spawn / NPC / portal home)
@export var park_chance: float = 0.16    # fraction of blocks left as green parks
@export var floor_height: float = 3.2    # meters per building "floor"
@export var min_floors: int = 2
@export var max_floors: int = 12
@export var noise_seed: int = 2077
@export var add_curbs: bool = true       # low car-only ramp curbs at road/sidewalk edges
@export var curb_height: float = 0.15    # how tall the curb bump is
@export var curb_base: float = 1.6       # ramp width (wider = gentler slope, easier to mount)
const CURB_LAYER := 5                     # car masks this; the player ignores it (steps over freely)

var _ground := FastNoiseLite.new()

func _pitch() -> float:
	return block_size + road_width   # road centerlines sit on multiples of this

func _ready() -> void:
	add_to_group("island")   # reuse every height_at() consumer unchanged
	_ground.seed = noise_seed
	_ground.frequency = 0.008
	_ground.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_build_ground()
	_build_city()
	if add_curbs:
		_build_curbs()

# World height at a given x/z — the source of truth, same signature as the island.
# The city is intentionally flat-ish (walkable everywhere, no water).
func height_at(x: float, z: float) -> float:
	return base_height + _ground.get_noise_2d(x, z) * roll_amp

# The whole city is dry ground — heads may roam anywhere (no water to avoid).
func is_walkable(_x: float, _z: float) -> bool:
	return true

# --- Deterministic grid helpers -----------------------------------------------
# A per-block hash keeps the ground COLOR and the BUILDING geometry in agreement
# without storing anything: both call the same pure functions of block index.

func _hash01(a: int, b: int, salt: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (noise_seed * 83492791) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0x7fffffff) / 2147483647.0

func _grid_dist(v: float) -> float:
	# Distance from the nearest road centerline (multiples of pitch).
	var p := _pitch()
	var m := fposmod(v, p)
	return minf(m, p - m)

func _is_road(x: float, z: float) -> bool:
	var hw := road_width * 0.5
	return _grid_dist(x) <= hw or _grid_dist(z) <= hw

func _block_index(v: float) -> int:
	return int(floor(v / _pitch()))

func _block_center(i: int) -> float:
	return (float(i) + 0.5) * _pitch()

func _block_is_park(ix: int, iz: int) -> bool:
	return _hash01(ix, iz, 7) < park_chance

# Does this block hold a building? (Not the plaza, not the clear rim, not a park.)
func _block_has_building(ix: int, iz: int) -> bool:
	var cx := _block_center(ix)
	var cz := _block_center(iz)
	var rim := extent - block_size
	if absf(cx) > rim or absf(cz) > rim:
		return false
	if Vector2(cx, cz).length() < plaza_radius:
		return false
	return not _block_is_park(ix, iz)

# Floors for a block's building — grows toward center, jittered per block.
func _building_floors(ix: int, iz: int) -> int:
	var cx := _block_center(ix)
	var cz := _block_center(iz)
	var t := clampf(1.0 - Vector2(cx, cz).length() / (extent * 0.9), 0.0, 1.0)
	var base_f := lerpf(float(min_floors), float(max_floors), t)
	var jitter := (_hash01(ix, iz, 5) - 0.5) * 4.0
	return clampi(int(round(base_f + jitter)), min_floors, max_floors + 3)

# World Y of the rooftop surface at x,z — or the ground height if no building is
# there. Used by rooftop artifacts (collectible.snap_to_roof) to sit up top.
func building_top_at(x: float, z: float) -> float:
	var ix := _block_index(x)
	var iz := _block_index(z)
	if not _block_has_building(ix, iz):
		return height_at(x, z)
	return height_at(_block_center(ix), _block_center(iz)) + _building_floors(ix, iz) * floor_height

# --- Ground mesh (colored by road / plaza / park / sidewalk) ------------------

func _color_for_pos(x: float, z: float) -> Color:
	if _is_road(x, z):
		return Color(0.20, 0.21, 0.23)              # asphalt
	if Vector2(x, z).length() < plaza_radius:
		return Color(0.55, 0.55, 0.58)              # central plaza pavers
	if _block_is_park(_block_index(x), _block_index(z)):
		return Color(0.30, 0.52, 0.26)              # park grass
	return Color(0.62, 0.62, 0.64)                  # sidewalk concrete

func _build_ground() -> void:
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
			# Wind so face normals point UP (needed for is_on_floor), matching island._tri.
			_tri(st, a, c, b)
			_tri(st, a, d, c)
	var mesh := st.commit()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.97
	mat.cull_mode = BaseMaterial3D.CULL_BACK

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.create_trimesh_collision()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(_color_for_pos(v.x, v.z))
		st.add_vertex(v)

# --- Buildings + parks --------------------------------------------------------
# One box building per block (taller toward the center → a skyline). Rendering
# uses a few bucketed MultiMeshes (one solid color each); collision is an exact
# per-building BoxShape3D static body. Park blocks get a scatter of trees instead.

func _build_city() -> void:
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE

	# Height-band buckets: gather per-instance transforms, then commit one
	# MultiMesh per band with its own material.
	var bands := [
		{"max": 4,   "color": Color(0.56, 0.57, 0.61), "xf": ([] as Array[Transform3D])},  # low concrete
		{"max": 7,   "color": Color(0.52, 0.45, 0.38), "xf": ([] as Array[Transform3D])},  # brick
		{"max": 10,  "color": Color(0.43, 0.49, 0.57), "xf": ([] as Array[Transform3D])},  # blue-grey
		{"max": 999, "color": Color(0.24, 0.28, 0.34), "xf": ([] as Array[Transform3D])},  # dark glass towers
	]
	var tree_xf: Array[Transform3D] = []
	var tree := _make_tree()

	var n := int(extent / _pitch())
	var rim := extent - block_size   # leave the outermost ring clear of buildings
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var cx := _block_center(ix)
			var cz := _block_center(iz)
			if absf(cx) > rim or absf(cz) > rim:
				continue
			if Vector2(cx, cz).length() < plaza_radius:
				continue                                  # keep the spawn plaza open
			if _block_is_park(ix, iz):
				_scatter_park_trees(ix, iz, cx, cz, tree_xf)
				continue

			var floors := _building_floors(ix, iz)
			var h := floors * floor_height
			var fw := block_size * lerpf(0.5, 0.78, _hash01(ix, iz, 11))
			var fd := block_size * lerpf(0.5, 0.78, _hash01(ix, iz, 13))

			var gy := height_at(cx, cz)
			var center := Vector3(cx, gy + h * 0.5, cz)
			var basis := Basis().scaled(Vector3(fw, h, fd))
			var xf := Transform3D(basis, center)

			for band in bands:
				if floors <= band["max"]:
					band["xf"].append(xf)
					break

			# Exact collision box (solid + walkable rooftop).
			var body := StaticBody3D.new()
			body.transform = Transform3D(Basis(), center)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(fw, h, fd)
			cs.shape = shape
			body.add_child(cs)
			add_child(body)

	for band in bands:
		_commit_multimesh(unit_box, band["xf"], band["color"])
	_commit_multimesh(tree, tree_xf, Color.WHITE, false)  # trees carry their own vertex colors

# Curbs ringing each block edge (= the road edges). They're shallow RAMP/speed-bump
# prisms (triangular cross-section), car-only collision, so even a low-riding car
# rolls up and over them from a dead stop instead of ramming a vertical wall.
func _build_curbs() -> void:
	var half := block_size * 0.5
	var n := int(extent / _pitch())
	var rim := extent - block_size
	# Shared prism mesh + convex shape (base along X, ridge along Z, length = block).
	var prism := PrismMesh.new()
	prism.size = Vector3(curb_base, curb_height, block_size)
	var shape := _prism_shape(curb_base, curb_height, block_size)
	# Rotating 90° about Y turns an X-running curb into a Z-running one.
	var rot_z := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
	var xf: Array[Transform3D] = []
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var cx := _block_center(ix)
			var cz := _block_center(iz)
			if absf(cx) > rim or absf(cz) > rim:
				continue
			if Vector2(cx, cz).length() < plaza_radius:
				continue
			# East/West edges run along Z (default prism orientation).
			_curb_prism(cx + half, cz, false, shape, rot_z, xf)
			_curb_prism(cx - half, cz, false, shape, rot_z, xf)
			# North/South edges run along X (rotate the prism 90°).
			_curb_prism(cx, cz + half, true, shape, rot_z, xf)
			_curb_prism(cx, cz - half, true, shape, rot_z, xf)
	_commit_multimesh(prism, xf, Color(0.72, 0.72, 0.74))

# Convex hull for a symmetric triangular prism, base on the ground, apex centered.
func _prism_shape(w: float, h: float, d: float) -> ConvexPolygonShape3D:
	var hw := w * 0.5
	var hh := h * 0.5
	var hd := d * 0.5
	var s := ConvexPolygonShape3D.new()
	s.points = PackedVector3Array([
		Vector3(-hw, -hh, -hd), Vector3(hw, -hh, -hd), Vector3(0, hh, -hd),
		Vector3(-hw, -hh, hd), Vector3(hw, -hh, hd), Vector3(0, hh, hd),
	])
	return s

func _curb_prism(px: float, pz: float, along_x: bool, shape: ConvexPolygonShape3D,
		rot_z: Transform3D, out: Array[Transform3D]) -> void:
	var basis := rot_z.basis if along_x else Basis()
	var pos := Vector3(px, height_at(px, pz) + curb_height * 0.5, pz)
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (CURB_LAYER - 1)   # layer 5 (value 16) — car-only
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = Transform3D(basis, pos)
	add_child(body)
	out.append(Transform3D(basis, pos))

func _scatter_park_trees(ix: int, iz: int, cx: float, cz: float, out: Array[Transform3D]) -> void:
	var half := block_size * 0.5 - 3.0
	for k in 5:
		var ox := (_hash01(ix * 31 + k, iz, 21) - 0.5) * 2.0 * half
		var oz := (_hash01(ix, iz * 31 + k, 23) - 0.5) * 2.0 * half
		var px := cx + ox
		var pz := cz + oz
		var s := lerpf(0.9, 1.7, _hash01(ix + k, iz - k, 27))
		var b := Basis(Vector3.UP, _hash01(k, ix + iz, 29) * TAU).scaled(Vector3(s, s, s))
		out.append(Transform3D(b, Vector3(px, height_at(px, pz), pz)))
		_add_trunk_collision(px, pz, s)

# A thin static collider on each tree trunk so the car (and player) can't drive
# straight through — bumps/stops on contact instead.
func _add_trunk_collision(px: float, pz: float, s: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45 * s
	shape.height = 4.5 * s
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(px, height_at(px, pz) + 2.0 * s, pz)
	add_child(body)

func _commit_multimesh(mesh: Mesh, xforms: Array[Transform3D], color: Color, colorize: bool = true) -> void:
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
	if colorize:
		mmi.material_override = _mat(color)
	add_child(mmi)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

# A simple stylized tree for park blocks (trunk + two cone tiers), one ArrayMesh
# with baked vertex colors so a single MultiMesh renders them all.
func _make_tree() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var brown := Color(0.34, 0.23, 0.14)
	var green := Color(0.18, 0.44, 0.24)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.24
	trunk.height = 1.4
	trunk.radial_segments = 6
	trunk.rings = 1
	_add_part(mesh, trunk, Transform3D(Basis(), Vector3(0, 0.7, 0)), brown)
	_cone(mesh, 1.2, 1.7, 1.7, green)
	_cone(mesh, 0.85, 1.5, 2.9, green)
	return mesh

func _cone(mesh: ArrayMesh, bottom_r: float, h: float, y: float, col: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = 7
	c.rings = 1
	_add_part(mesh, c, Transform3D(Basis(), Vector3(0, y, 0)), col)

func _add_part(mesh: ArrayMesh, prim: Mesh, xf: Transform3D, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(prim, 0, xf)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.96
	m.vertex_color_use_as_albedo = false
	st.set_material(m)
	# Bake the color into vertex colors too, so the shared MultiMesh material shows it.
	st.commit(mesh)
	var idx := mesh.get_surface_count() - 1
	mesh.surface_set_material(idx, m)
