extends Node3D
# SKY VALLEY — level 3. A whole landscape rather than one kind of ground,
# laid out like Jak & Daxter's first areas: a Sandover-style village by the
# beach in the south, a river running down from the mountains in the north
# (over a waterfall, past a hidden cave), jungle and meadow between, a small
# city to the west, a glowing mushroom forest and a volcano to the east, an
# ancient monolith field up in the mountains, and floating islands above it
# all, chained together with stepping stones up to a Sky Temple.
#
# Same contract as island.gd / city.gd: group "island", height_at(), is_walkable().
#
# How the ground is made: heights are computed ONCE into a grid (_h), and
# everything reads that grid — the mesh, the collision and height_at() — so
# they can never disagree. Each landmark is a "stamp" on that grid (raise the
# mountains, flatten the village, carve the river...). height_at() interpolates
# the exact triangle the mesh uses, not a bilinear blend.
#
# Tunnels: a heightfield can't have a hole in it, so the terrain is a TRIMESH
# (in chunks), and the triangles where a tunnel would poke through are left
# out. The tube itself is its own mesh. See _build_tunnels.
#
# Decoration (village, town, mushrooms, monoliths, sky islands, trees) lives in
# valley_decor.gd, built after the ground exists.

@export var extent: float = 400.0          # half-width: the map spans -extent..extent (800 m)
@export var cell: float = 3.2              # terrain grid spacing (m)
@export var chunks: int = 10               # terrain split into chunks x chunks pieces (culling)
@export var noise_seed: int = 3033
@export var water_level: float = 0.0       # the sea, to the south. enemy.gd's drown check reads it
@export var river_depth: float = 1.6       # water surface above the bed — wadeable
@export var river_half_width: float = 7.0
@export var river_bank: float = 11.0
@export var lava_damage_pop: float = 22.0  # how high lava throws you (Jak-style)

# Landmark centres (x, z). North is -z.
const VILLAGE := Vector2(30, 215)
const TOWN := Vector2(-255, 60)
const TOWN_HALF := 80.0
const TOWN_PITCH := 48.0
const SHROOMS := Vector2(225, 40)
const VOLCANO := Vector2(255, -235)
const MONOLITHS := Vector2(-140, -235)
const PLATEAU_Y := 50.0
const SHELF_Y := 64.0                      # the high ground above the waterfall
const VOLCANO_H := 195.0                   # towers over the range (peaks ~100-140)
const VOLCANO_R := 205.0                   # foot of the cone
const CRATER_R := 32.0
# Rim height falls out of the cone formula; the bowl sinks 22 m below it and
# the lava sits 7 m above the bowl's floor.
const RIM_Y := VOLCANO_H * 0.7752          # == VOLCANO_H * pow(1 - CRATER_R / VOLCANO_R, 1.5)
const LAVA_Y := RIM_Y - 15.0               # crater lava surface
const LAVA_POOL := Vector2(203, -95)
const LAVA_POOL_R := 12.0

# The river, source to sea: (x, design bed height, z). Beds are lowered further
# where the land is lower (see _plan_river), so water never sits above its banks.
const RIVER: Array[Vector3] = [
	Vector3(70, 92, -335),
	Vector3(55, 76, -280),
	Vector3(45, 62, -215),
	Vector3(40, 60, -173),    # waterfall lip ...
	Vector3(40, 14, -162),    # ... and the plunge pool below it
	Vector3(30, 12, -120),
	Vector3(45, 10, -60),
	Vector3(85, 8, -5),
	Vector3(75, 7, 60),
	Vector3(100, 6, 120),
	Vector3(82, 4, 175),
	Vector3(72, 2, 240),
	Vector3(60, 0, 290),
	Vector3(55, -1, 345),
]
const FALL_SEG := 3            # RIVER[3] -> RIVER[4] is the waterfall

# Lava runs out of a notch in the crater rim, down the south-west flank, into a
# pool at the edge of the mushroom forest. Beds after the first follow the slope.
const LAVA_FLOW: Array[Vector2] = [
	Vector2(237, -212), Vector2(226, -190), Vector2(215, -160),
	Vector2(207, -125), Vector2(203, -95),
]
const LAVA_HALF_WIDTH := 3.5

# Tunnels: floor centreline (x, z); floor heights come from the ground at the
# two mouths. Ridge Tunnel joins the small city side to the monolith plateau;
# the Waterfall Cave climbs from the plunge pool up to the shelf above the falls.
const TUNNELS: Array[Dictionary] = [
	{"name": "Ridge Tunnel", "r": 5.0,
		"path": [Vector2(-225, -95), Vector2(-205, -140), Vector2(-150, -182)]},
	{"name": "Waterfall Cave", "r": 4.5,
		"path": [Vector2(56, -158), Vector2(80, -185), Vector2(115, -205), Vector2(100, -240)]},
]

var _n := 0                                 # grid cells per side
var _h := PackedFloat32Array()              # (n+1)^2 final heights
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _mount := FastNoiseLite.new()
var _coast := FastNoiseLite.new()
var _tint := FastNoiseLite.new()

# Resampled river / lava / tunnel paths: points, cumulative lengths, heights.
var _river_pts := PackedVector2Array()
var _river_cum := PackedFloat32Array()
var _river_bed := PackedFloat32Array()
var _fall_s := Vector2.ZERO                  # [start, end] arc length of the waterfall
var _river_box := Rect2()                    # quick reject before walking the river
var _lava_box := Rect2()
var _lava_pts := PackedVector2Array()
var _lava_cum := PackedFloat32Array()
var _lava_bed := PackedFloat32Array()
var _tunnels: Array[Dictionary] = []        # {pts, cum, floor(PackedFloat32Array), r, name}

var _player: Node3D = null
var _water_mat: ShaderMaterial
var _lava_mat: ShaderMaterial

func _ready() -> void:
	add_to_group("island")
	for nz in [[_hills, 0.012, 1], [_detail, 0.05, 2], [_mount, 0.009, 3], [_coast, 0.01, 4], [_tint, 0.03, 5]]:
		var fn: FastNoiseLite = nz[0]
		fn.seed = noise_seed + nz[2]
		fn.frequency = nz[1]
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://assets/materials/water_flow.gdshader")
	_lava_mat = ShaderMaterial.new()
	_lava_mat.shader = load("res://assets/materials/lava.gdshader")

	_n = int(round(extent * 2.0 / cell))
	_plan_tunnels()       # tunnel floors read the ground BEFORE cover/carving
	_plan_river()
	_plan_lava()
	_build_heights()
	_build_terrain()
	_build_sea()
	_build_river_water()
	_build_waterfall()
	_build_lava()
	_build_tunnels()
	var decor = load("res://scripts/valley_decor.gd").new()
	decor.name = "Decor"
	decor.valley = self
	add_child(decor)

# --- Public contract ------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var fx := clampf((x + extent) / cell, 0.0, float(_n) - 0.0001)
	var fz := clampf((z + extent) / cell, 0.0, float(_n) - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var ha := _h[i * (_n + 1) + j]               # (x0, z0)
	var hb := _h[i * (_n + 1) + j + 1]           # (x0, z1)
	var hc := _h[(i + 1) * (_n + 1) + j + 1]     # (x1, z1)
	var hd := _h[(i + 1) * (_n + 1) + j]         # (x1, z0)
	# The same two triangles the mesh is made of (split along a-c).
	if v > u:
		return ha + v * (hb - ha) + u * (hc - hb)
	return ha + u * (hd - ha) + v * (hc - hd)

# Heads roam dry, not-too-steep ground that isn't lava or the river channel.
func is_walkable(x: float, z: float) -> bool:
	var h := height_at(x, z)
	if h < 1.5 or lava_surface_at(x, z) > -INF:
		return false
	if river_distance(x, z) < river_half_width + 2.0:
		return false
	var gx := height_at(x + 2.0, z) - height_at(x - 2.0, z)
	var gz := height_at(x, z + 2.0) - height_at(x, z - 2.0)
	return Vector2(gx, gz).length() / 4.0 < 0.7

func river_distance(x: float, z: float) -> float:
	return _poly_nearest(_river_pts, _river_cum, Vector2(x, z), 1e9).x

# World Y of the lava surface at x,z, or -INF if there's no lava there.
func lava_surface_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if p.distance_to(VOLCANO) < CRATER_R * 0.62:
		return LAVA_Y
	if p.distance_to(LAVA_POOL) < LAVA_POOL_R:
		return _lava_bed[_lava_bed.size() - 1] + 1.0
	var hit := _poly_nearest(_lava_pts, _lava_cum, p, LAVA_HALF_WIDTH)
	if hit.x <= LAVA_HALF_WIDTH:
		return _sample_profile(_lava_cum, _lava_bed, hit.y) + 1.0
	return -INF

func is_in_town(x: float, z: float) -> bool:
	return absf(x - TOWN.x) < TOWN_HALF + 6.0 and absf(z - TOWN.y) < TOWN_HALF + 6.0

func is_town_road(x: float, z: float) -> bool:
	if not is_in_town(x, z):
		return false
	var lx := x - TOWN.x
	var lz := z - TOWN.y
	return _road_line(lx) or _road_line(lz)

func _road_line(v: float) -> bool:
	var m := fposmod(v - TOWN_PITCH * 0.5, TOWN_PITCH)
	return minf(m, TOWN_PITCH - m) < 5.0

func tunnel_list() -> Array[Dictionary]:
	return _tunnels

func river_points() -> PackedVector2Array:
	return _river_pts

func river_bed_at_s(s: float) -> float:
	return _sample_profile(_river_cum, _river_bed, s)

# Street lamps in the small city, lanterns around the village (lamps.gd).
func lamp_spots() -> Array:
	var d = get_node_or_null("Decor")
	return d.lamp_spots() if d else []

# --- Polylines -----------------------------------------------------------------

# Nearest point on a polyline to p: Vector3(distance, arc length, 1 if the
# nearest point is strictly inside the line, 0 if it clamped to an end).
# Segments further than `maxd` away are skipped cheaply.
func _poly_nearest(pts: PackedVector2Array, cum: PackedFloat32Array, p: Vector2, maxd: float) -> Vector3:
	var best := INF
	var best_s := 0.0
	var inside := 0.0
	var last := pts.size() - 2
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		if p.x < minf(a.x, b.x) - maxd or p.x > maxf(a.x, b.x) + maxd \
				or p.y < minf(a.y, b.y) - maxd or p.y > maxf(a.y, b.y) + maxd:
			continue
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 < 0.0001:
			continue
		var raw := (p - a).dot(ab) / l2
		var t := clampf(raw, 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_s = cum[k] + t * sqrt(l2)
			inside = 0.0 if ((k == 0 and raw < 0.0) or (k == last and raw > 1.0)) else 1.0
	return Vector3(best, best_s, inside)

func _cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var acc := 0.0
	for k in pts.size():
		if k > 0:
			acc += pts[k].distance_to(pts[k - 1])
		cum[k] = acc
	return cum

# Linear lookup of a per-point profile (bed height, floor height) by arc length.
func _sample_profile(cum: PackedFloat32Array, vals: PackedFloat32Array, s: float) -> float:
	if s <= cum[0]:
		return vals[0]
	for k in range(1, cum.size()):
		if s <= cum[k]:
			var span := cum[k] - cum[k - 1]
			var t := (s - cum[k - 1]) / span if span > 0.0001 else 0.0
			return lerpf(vals[k - 1], vals[k], t)
	return vals[vals.size() - 1]

func _resample(src: Array, step: float, keep_seg: int = -1) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in src.size() - 1:
		var a: Vector2 = src[k]
		var b: Vector2 = src[k + 1]
		var n := 1 if k == keep_seg else maxi(1, int(ceil(a.distance_to(b) / step)))
		for m in n:
			out.append(a.lerp(b, float(m) / n))
	out.append(src[src.size() - 1])
	return out

# --- Planning paths (before the height grid) ----------------------------------

func _plan_tunnels() -> void:
	for t in TUNNELS:
		var pts := _resample(t["path"], 2.5)
		var cum := _cumulative(pts)
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[pts.size() - 1]
		var fa := _shape_height(a.x, a.y, false)
		var fb := _shape_height(b.x, b.y, false)
		var floors := PackedFloat32Array()
		floors.resize(pts.size())
		for k in pts.size():
			floors[k] = lerpf(fa, fb, cum[k] / cum[cum.size() - 1])
		var box := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			box = box.expand(q)
		box = box.grow(float(t["r"]) + 42.0)
		_tunnels.append({"name": t["name"], "r": t["r"], "pts": pts, "cum": cum, "floor": floors, "box": box})

func _plan_river() -> void:
	var src: Array = []
	for p in RIVER:
		src.append(Vector2(p.x, p.z))
	_river_pts = _resample(src, 5.0, FALL_SEG)
	_river_cum = _cumulative(_river_pts)
	# Design beds, interpolated per resampled point.
	var design_cum := _cumulative(PackedVector2Array(src))
	var design_bed := PackedFloat32Array()
	for p in RIVER:
		design_bed.append(p.y)
	_river_bed.resize(_river_pts.size())
	var running := INF
	for k in _river_pts.size():
		var p := _river_pts[k]
		var hit := _poly_nearest(PackedVector2Array(src), design_cum, p, 1.0)
		var bed := _sample_profile(design_cum, design_bed, hit.y)
		# Below its own banks, so the water never sits on top of the grass.
		var side := Vector2(0, 0)
		if k + 1 < _river_pts.size():
			var dir := (_river_pts[k + 1] - p).normalized()
			side = Vector2(-dir.y, dir.x) * (river_half_width + 2.0)
		var low := minf(_shape_height(p.x, p.y, true),
			minf(_shape_height(p.x + side.x, p.y + side.y, true), _shape_height(p.x - side.x, p.y - side.y, true)))
		bed = minf(bed, low - river_depth - 0.9)
		running = minf(running, bed)      # water only runs downhill
		_river_bed[k] = running
	_fall_s = Vector2(_river_cum[_index_of_design(FALL_SEG)], _river_cum[_index_of_design(FALL_SEG + 1)])
	_river_box = Rect2(_river_pts[0], Vector2.ZERO)
	for q in _river_pts:
		_river_box = _river_box.expand(q)
	_river_box = _river_box.grow(75.0)

# Index into _river_pts of design point `d` (resampling keeps every design point).
func _index_of_design(d: int) -> int:
	var target := Vector2(RIVER[d].x, RIVER[d].z)
	for k in _river_pts.size():
		if _river_pts[k].distance_to(target) < 0.01:
			return k
	return 0

func _plan_lava() -> void:
	_lava_pts = _resample(LAVA_FLOW, 4.0)
	_lava_cum = _cumulative(_lava_pts)
	_lava_bed.resize(_lava_pts.size())
	var running := LAVA_Y - 2.0
	for k in _lava_pts.size():
		var p := _lava_pts[k]
		var bed := LAVA_Y - 2.0 if k == 0 else _shape_height(p.x, p.y, true) - 2.6
		running = minf(running, bed)
		_lava_bed[k] = running
	_lava_box = Rect2(_lava_pts[0], Vector2.ZERO)
	for q in _lava_pts:
		_lava_box = _lava_box.expand(q)
	_lava_box = _lava_box.grow(15.0)

# --- The height grid -----------------------------------------------------------

func _build_heights() -> void:
	_h.resize((_n + 1) * (_n + 1))
	for i in _n + 1:
		var x := -extent + i * cell
		for j in _n + 1:
			var z := -extent + j * cell
			_h[i * (_n + 1) + j] = _final_height(x, z)

# Everything except the river and lava carving. `with_cover` adds the ridges
# that keep the tunnels underground (off while planning tunnel floors).
func _shape_height(x: float, z: float, with_cover: bool) -> float:
	var h := 8.0 + _hills.get_noise_2d(x, z) * 5.0 + _detail.get_noise_2d(x, z) * 1.2
	var ridged := 1.0 - absf(_mount.get_noise_2d(x, z))
	# Mountains along the whole north edge.
	var north := smoothstep(-110.0, -300.0, z)
	h += north * (52.0 + ridged * ridged * 88.0)
	# Hills closing off the east and west edges.
	var side := smoothstep(330.0, 395.0, absf(x))
	h += side * (45.0 + ridged * 40.0)
	# The shelf above the waterfall: a cliff (the scarp) around the river.
	var shelf_mask := 1.0 - smoothstep(130.0, 190.0, absf(x - 40.0))
	var scarp := smoothstep(-160.0, -172.0, z)
	h = lerpf(h, maxf(h, SHELF_Y + _detail.get_noise_2d(x, z) * 2.0), scarp * shelf_mask)
	# Flattened places: the small city, the village, the monolith plateau, and
	# the low, damp hollow of the mushroom forest.
	h = _flatten(h, x, z, TOWN, 95.0, 125.0, 6.0)
	h = _flatten(h, x, z, VILLAGE, 50.0, 95.0, 5.0 + _hills.get_noise_2d(x, z) * 1.2)
	h = _flatten(h, x, z, MONOLITHS, 62.0, 100.0, PLATEAU_Y + _detail.get_noise_2d(x, z) * 1.5)
	h = _flatten(h, x, z, SHROOMS, 85.0, 130.0, 4.0 + _hills.get_noise_2d(x, z) * 2.5)
	# The volcano: a concave cone with a crater bowl at the top.
	var r := Vector2(x, z).distance_to(VOLCANO)
	var cone := VOLCANO_H * pow(clampf(1.0 - r / VOLCANO_R, 0.0, 1.0), 1.5)
	if r < CRATER_R:
		cone = RIM_Y - 22.0 + pow(r / CRATER_R, 2.0) * 22.0
	h = maxf(h, cone) if r >= CRATER_R else cone
	# Beach and sea along the south edge, with a wobbly coastline.
	var coast := 300.0 + _coast.get_noise_2d(x * 0.5, 0.0) * 25.0
	var sea := smoothstep(coast - 60.0, coast + 35.0, z)
	h = lerpf(h, -12.0, sea)
	# Every other edge drops into the sea too: Sky Valley is an island ringed by
	# mountains, so from the air there's ocean all round instead of a map edge.
	var rim := smoothstep(370.0, 398.0, maxf(absf(x), absf(z)))
	h = lerpf(h, -14.0, rim)
	if with_cover:
		h = _tunnel_cover(h, x, z)
	return h

func _flatten(h: float, x: float, z: float, c: Vector2, r_in: float, r_out: float, target: float) -> float:
	var w := 1.0 - smoothstep(r_in, r_out, Vector2(x, z).distance_to(c))
	return lerpf(h, target, w)

# A ridge over each tunnel's middle, so it really is underground. It fades out
# at both ends, which leaves the mouths opening in a hillside.
func _tunnel_cover(h: float, x: float, z: float) -> float:
	for t in _tunnels:
		if not (t["box"] as Rect2).has_point(Vector2(x, z)):
			continue
		var r: float = t["r"]
		var hit := _poly_nearest(t["pts"], t["cum"], Vector2(x, z), r + 40.0)
		if hit.x > r + 40.0:
			continue
		var cum: PackedFloat32Array = t["cum"]
		var tn := hit.y / cum[cum.size() - 1]
		var ramp := smoothstep(0.0, 0.035, tn) * smoothstep(1.0, 0.965, tn)
		var need := _sample_profile(cum, t["floor"], hit.y) + r * 1.15 + 7.0 + _detail.get_noise_2d(x, z) * 3.0
		var w := 1.0 - smoothstep(r + 6.0, r + 40.0, hit.x)
		h = maxf(h, lerpf(h, need, w * ramp))
	return h

func _final_height(x: float, z: float) -> float:
	var h := _shape_height(x, z, true)
	# River: a flat bed with sloping banks.
	var p := Vector2(x, z)
	var rv := _poly_nearest(_river_pts, _river_cum, p, river_half_width + river_bank) if _river_box.has_point(p) else Vector3(INF, 0, 0)
	if rv.x < river_half_width + river_bank:
		var bed := _sample_profile(_river_cum, _river_bed, rv.y)
		var w := smoothstep(river_half_width, river_half_width + river_bank, rv.x)
		h = minf(h, lerpf(bed, h, w))
	# Lava channel and pool.
	var lv := _poly_nearest(_lava_pts, _lava_cum, p, LAVA_HALF_WIDTH + 5.0) if _lava_box.has_point(p) else Vector3(INF, 0, 0)
	if lv.x < LAVA_HALF_WIDTH + 5.0:
		var bed := _sample_profile(_lava_cum, _lava_bed, lv.y)
		var w := smoothstep(LAVA_HALF_WIDTH, LAVA_HALF_WIDTH + 5.0, lv.x)
		h = minf(h, lerpf(bed, h, w))
	var pd := p.distance_to(LAVA_POOL)
	if pd < LAVA_POOL_R + 8.0:
		var bed := _lava_bed[_lava_bed.size() - 1] - 0.5
		h = minf(h, lerpf(bed, h, smoothstep(LAVA_POOL_R, LAVA_POOL_R + 8.0, pd)))
	return h

func _gi(i: int, j: int) -> float:
	return _h[clampi(i, 0, _n) * (_n + 1) + clampi(j, 0, _n)]

# --- Terrain mesh + collision ---------------------------------------------------

func _build_terrain() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var colors := _vertex_colors()
	var per := int(ceil(float(_n) / chunks))
	for ci in chunks:
		for cj in chunks:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			for i in range(ci * per, mini((ci + 1) * per, _n)):
				for j in range(cj * per, mini((cj + 1) * per, _n)):
					var x0 := -extent + i * cell
					var z0 := -extent + j * cell
					var a := Vector3(x0, _gi(i, j), z0)
					var b := Vector3(x0, _gi(i, j + 1), z0 + cell)
					var c := Vector3(x0 + cell, _gi(i + 1, j + 1), z0 + cell)
					var d := Vector3(x0 + cell, _gi(i + 1, j), z0)
					var ca := colors[i * (_n + 1) + j]
					var cb := colors[i * (_n + 1) + j + 1]
					var cc := colors[(i + 1) * (_n + 1) + j + 1]
					var cd := colors[(i + 1) * (_n + 1) + j]
					# Wound so normals face UP (is_on_floor needs it).
					_tri(verts, norms, cols, a, c, b, ca, cc, cb)
					_tri(verts, norms, cols, a, d, c, ca, cd, cc)
			if verts.is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_COLOR] = cols
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			add_child(mi)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(verts)
			cs.shape = shape
			body.add_child(cs)
			add_child(body)

# Adds one flat-shaded triangle — unless a tunnel runs through it, in which
# case it's left out, and that gap is the tunnel's mouth.
func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var mid := (a + b + c) / 3.0
	if _cut_by_tunnel(mid):
		return
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	verts.append(a); verts.append(b); verts.append(c)
	norms.append(n); norms.append(n); norms.append(n)
	cols.append(ca); cols.append(cb); cols.append(cc)

func _cut_by_tunnel(p: Vector3) -> bool:
	for t in _tunnels:
		if not (t["box"] as Rect2).has_point(Vector2(p.x, p.z)):
			continue
		var r: float = t["r"]
		var hit := _poly_nearest(t["pts"], t["cum"], Vector2(p.x, p.z), r + 1.0)
		if hit.x > r + 1.0 or hit.z < 0.5:
			continue
		var fl := _sample_profile(t["cum"], t["floor"], hit.y)
		if p.y < fl + r * 1.15 + 0.8 and p.y > fl - 1.5:
			return true
	return false

# --- Colours --------------------------------------------------------------------

func _vertex_colors() -> PackedColorArray:
	var cols := PackedColorArray()
	cols.resize((_n + 1) * (_n + 1))
	for i in _n + 1:
		var x := -extent + i * cell
		for j in _n + 1:
			var z := -extent + j * cell
			var h := _gi(i, j)
			var gx := (_gi(i + 1, j) - _gi(i - 1, j)) / (2.0 * cell)
			var gz := (_gi(i, j + 1) - _gi(i, j - 1)) / (2.0 * cell)
			var steep := Vector2(gx, gz).length()
			cols[i * (_n + 1) + j] = _color_at(x, z, h, steep)
	return cols

func _color_at(x: float, z: float, h: float, steep: float) -> Color:
	var p := Vector2(x, z)
	var tint := _tint.get_noise_2d(x, z) * 0.5 + 0.5
	var c := Color(0.30, 0.54, 0.24).lerp(Color(0.42, 0.62, 0.28), tint)        # meadow
	var rd := _poly_nearest(_river_pts, _river_cum, p, 72.0).x if _river_box.has_point(p) else INF
	if rd < 70.0 and z > -160.0 and z < 200.0:                                     # jungle by the river
		c = c.lerp(Color(0.16, 0.42, 0.20), (1.0 - rd / 70.0) * 0.8)
	# Mushroom forest moss: violet and teal.
	var sw := 1.0 - smoothstep(80.0, 125.0, p.distance_to(SHROOMS))
	if sw > 0.0:
		var moss := Color(0.30, 0.20, 0.44).lerp(Color(0.12, 0.36, 0.40), tint)
		c = c.lerp(moss, sw)
	# Monolith plateau: pale, worn stone-grass.
	var mw := 1.0 - smoothstep(55.0, 95.0, p.distance_to(MONOLITHS))
	if mw > 0.0:
		c = c.lerp(Color(0.46, 0.48, 0.42), mw * 0.85)
	# Village: a packed-dirt square in the middle.
	if p.distance_to(VILLAGE) < 22.0:
		c = Color(0.56, 0.46, 0.32)
	# Rock on steep or high ground, snow on the peaks.
	if steep > 0.85 or h > 62.0 and mw <= 0.0:
		c = c.lerp(Color(0.46, 0.44, 0.41), clampf((steep - 0.6) * 2.0, 0.0, 1.0) if steep > 0.85 else smoothstep(62.0, 80.0, h))
	if h > 100.0 + tint * 12.0:
		c = Color(0.93, 0.95, 0.98)
	# The volcano: dark basalt, reddening toward the lava.
	var vr := p.distance_to(VOLCANO)
	if vr < VOLCANO_R:
		var basalt := Color(0.12, 0.10, 0.10).lerp(Color(0.20, 0.16, 0.14), tint)
		c = c.lerp(basalt, 1.0 - smoothstep(VOLCANO_R * 0.6, VOLCANO_R * 0.95, vr))
	var lava_d := _poly_nearest(_lava_pts, _lava_cum, p, 12.0).x if _lava_box.has_point(p) else INF
	var near_lava := minf(lava_d, minf(p.distance_to(LAVA_POOL) - LAVA_POOL_R, vr - CRATER_R * 0.6))
	if near_lava < 10.0:
		c = c.lerp(Color(0.38, 0.11, 0.05), 1.0 - near_lava / 10.0)
	# The small city: asphalt roads and pale pavement.
	if is_in_town(x, z):
		c = Color(0.21, 0.22, 0.24) if is_town_road(x, z) else Color(0.60, 0.60, 0.62)
	# River bed pebbles, then sand along the coast.
	if rd < river_half_width + 1.5:
		c = Color(0.44, 0.41, 0.34)
	if h < 3.2 and z > 180.0:
		c = Color(0.86, 0.79, 0.57).lerp(Color(0.70, 0.62, 0.45), clampf((1.0 - h) * 0.3, 0.0, 1.0))
	return c

# --- Water ------------------------------------------------------------------------

func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 6.0, extent * 6.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.42, 0.62, 0.66)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.2
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, water_level, 0)
	add_child(mi)

# A ribbon down the river's centreline, its UVs running downstream so the
# shader's foam streaks travel with the current. The waterfall is separate.
func _build_river_water() -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var hw := river_half_width + 2.5
	var row := 0
	for k in _river_pts.size():
		var s := _river_cum[k]
		var p := _river_pts[k]
		var after_fall := s >= _fall_s.y
		if s > _fall_s.x and s < _fall_s.y:
			continue
		var dir: Vector2
		if k + 1 < _river_pts.size():
			dir = (_river_pts[k + 1] - p).normalized()
		else:
			dir = (p - _river_pts[k - 1]).normalized()
		var side := Vector2(-dir.y, dir.x) * hw
		var y := maxf(_river_bed[k] + river_depth, water_level + 0.05)
		verts.append(Vector3(p.x + side.x, y, p.y + side.y))
		verts.append(Vector3(p.x - side.x, y, p.y - side.y))
		uvs.append(Vector2(0, s / 8.0))
		uvs.append(Vector2(1, s / 8.0))
		# Don't bridge the gap across the waterfall.
		if row > 0 and not (after_fall and _river_cum[k - 1] <= _fall_s.x + 0.01 and s <= _fall_s.y + 0.01):
			var a := (row - 1) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		row += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = mesh
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# The falls: a sheet that leaves the lip, curls over and drops into the pool,
# fast-streaked white, with mist where it lands.
func _build_waterfall() -> void:
	var top := Vector3(RIVER[FALL_SEG].x, _sample_profile(_river_cum, _river_bed, _fall_s.x) + river_depth, RIVER[FALL_SEG].z)
	var bottom := Vector3(RIVER[FALL_SEG + 1].x, _sample_profile(_river_cum, _river_bed, _fall_s.y) + river_depth, RIVER[FALL_SEG + 1].z)
	var flow := Vector3(bottom.x - top.x, 0, bottom.z - top.z).normalized()
	var side := flow.cross(Vector3.UP).normalized() * (river_half_width + 1.0)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var steps := 16
	var drop := top.y - bottom.y
	var reach := Vector2(bottom.x - top.x, bottom.z - top.z).length()
	for m in steps + 1:
		var t := float(m) / steps
		# Out over the lip quickly, then nearly straight down.
		var along := reach * (1.0 - pow(1.0 - t, 3.0))
		var p := top + flow * along + Vector3.DOWN * drop * t * t
		verts.append(p + side)
		verts.append(p - side)
		uvs.append(Vector2(0, t * drop / 6.0))
		uvs.append(Vector2(1, t * drop / 6.0))
		if m > 0:
			var a := (m - 1) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := _water_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("speed", 2.2)
	mat.set_shader_parameter("foam_amount", 0.45)
	mat.set_shader_parameter("stretch", 0.25)
	var mi := MeshInstance3D.new()
	mi.name = "Waterfall"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	add_child(_mist(bottom + Vector3.UP * 1.0, Vector3(river_half_width, 1.5, 3.0), Color(0.9, 0.96, 1.0, 0.35), 3.5))

# Soft billowing puffs (waterfall spray, volcano smoke).
func _mist(at: Vector3, box: Vector3, color: Color, size: float, amount: int = 60,
		life: float = 3.0, rise: float = 2.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = rise * 0.5
	pm.initial_velocity_max = rise
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(color.r, color.g, color.b, color.a))
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _soft_dot()
	quad.material = qm
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = life
	ps.process_material = pm
	ps.draw_pass_1 = quad
	ps.position = at
	ps.visibility_aabb = AABB(-box - Vector3(10, 10, 10), box * 2.0 + Vector3(20, rise * life + 30.0, 20))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ps

var _dot_tex: Texture2D = null
func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_dot_tex = t
	return _dot_tex

func soft_dot() -> Texture2D:
	return _soft_dot()

func make_mist(at: Vector3, box: Vector3, color: Color, size: float, amount: int = 60,
		life: float = 3.0, rise: float = 2.0) -> GPUParticles3D:
	return _mist(at, box, color, size, amount, life, rise)

# --- Lava -------------------------------------------------------------------------

func _build_lava() -> void:
	# Crater pool.
	var disc := CylinderMesh.new()
	disc.top_radius = CRATER_R * 0.75
	disc.bottom_radius = CRATER_R * 0.75
	disc.height = 0.2
	disc.radial_segments = 40
	var crater := MeshInstance3D.new()
	crater.mesh = disc
	crater.material_override = _lava_mat
	crater.position = Vector3(VOLCANO.x, LAVA_Y, VOLCANO.y)
	crater.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crater)
	# The pool at the bottom.
	var pool_disc := CylinderMesh.new()
	pool_disc.top_radius = LAVA_POOL_R + 1.5
	pool_disc.bottom_radius = LAVA_POOL_R + 1.5
	pool_disc.height = 0.2
	pool_disc.radial_segments = 32
	var pool := MeshInstance3D.new()
	pool.mesh = pool_disc
	pool.material_override = _lava_mat
	pool.position = Vector3(LAVA_POOL.x, _lava_bed[_lava_bed.size() - 1] + 1.0, LAVA_POOL.y)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	# The channel between them.
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in _lava_pts.size():
		var p := _lava_pts[k]
		var dir: Vector2 = (_lava_pts[mini(k + 1, _lava_pts.size() - 1)] - _lava_pts[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x) * (LAVA_HALF_WIDTH + 1.2)
		var y := _lava_bed[k] + 1.0
		verts.append(Vector3(p.x + side.x, y, p.y + side.y))
		verts.append(Vector3(p.x - side.x, y, p.y - side.y))
		if k > 0:
			var a := (k - 1) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var ch := MeshInstance3D.new()
	ch.mesh = mesh
	ch.material_override = _lava_mat
	ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ch)
	# Glow, smoke and embers.
	for spot in [Vector3(VOLCANO.x, LAVA_Y + 6.0, VOLCANO.y), Vector3(LAVA_POOL.x, pool.position.y + 4.0, LAVA_POOL.y)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.45, 0.15)
		l.light_energy = 5.0
		l.omni_range = 55.0
		l.position = spot
		add_child(l)
	add_child(_mist(Vector3(VOLCANO.x, LAVA_Y + 4.0, VOLCANO.y), Vector3(14, 2, 14),
		Color(0.32, 0.30, 0.30, 0.55), 26.0, 40, 14.0, 9.0))
	add_child(_mist(Vector3(VOLCANO.x, LAVA_Y + 1.0, VOLCANO.y), Vector3(16, 1, 16),
		Color(1.0, 0.55, 0.15, 0.9), 0.7, 80, 3.0, 7.0))

# --- Tunnels ---------------------------------------------------------------------

# Each tunnel is an arched tube along its floor line: a flat floor and a
# half-round roof. Drawn from both sides (it's also the rock you see in the
# mouth), with a stone arch at each end and glowing crystals inside.
func _build_tunnels() -> void:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.36, 0.33, 0.31)
	rock.roughness = 0.95
	rock.cull_mode = BaseMaterial3D.CULL_DISABLED
	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = Color(0.4, 0.9, 1.0)
	crystal.emission_enabled = true
	crystal.emission = Color(0.3, 0.85, 1.0)
	crystal.emission_energy_multiplier = 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed + 77
	for t in _tunnels:
		var pts: PackedVector2Array = t["pts"]
		var floors: PackedFloat32Array = t["floor"]
		var r: float = t["r"]
		var ring := 12
		var verts := PackedVector3Array()
		for k in pts.size() - 1:
			var f0 := _tunnel_frame(pts, floors, k)
			var f1 := _tunnel_frame(pts, floors, k + 1)
			for m in ring:
				var a0 := _arch_point(f0, r, m, ring)
				var a1 := _arch_point(f0, r, m + 1, ring)
				var b0 := _arch_point(f1, r, m, ring)
				var b1 := _arch_point(f1, r, m + 1, ring)
				verts.append_array([a0, b0, a1, a1, b0, b1])
			# Floor (faces up).
			var fl0 := _arch_point(f0, r, 0, ring)
			var fr0 := _arch_point(f0, r, ring, ring)
			var fl1 := _arch_point(f1, r, 0, ring)
			var fr1 := _arch_point(f1, r, ring, ring)
			_append_up(verts, fl0, fr0, fl1)
			_append_up(verts, fr0, fr1, fl1)
			# Crystals every so often.
			if k % 6 == 3:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				_crystal_cluster(f0, side, r, crystal, rng)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in verts:
			st.add_vertex(v)
		st.generate_normals()
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = t["name"]
		mi.mesh = mesh
		mi.material_override = rock
		add_child(mi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(verts)
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		# Stone arches framing both mouths.
		for end in [0, pts.size() - 1]:
			var fr := _tunnel_frame(pts, floors, end)
			var arch := TorusMesh.new()
			arch.inner_radius = r - 0.2
			arch.outer_radius = r + 1.4
			arch.rings = 24
			arch.ring_segments = 8
			var ami := MeshInstance3D.new()
			ami.mesh = arch
			ami.material_override = rock
			# Torus lies in XZ; stand it up across the tunnel.
			var fwd: Vector3 = fr["fwd"]
			ami.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), fr["o"])
			add_child(ami)
			# A rock gateway round the opening: pillars either side and a lintel
			# over the top. The ground grid is coarse next to a 5 m tunnel, so the
			# cut in the hillside is jagged; this frames it and hides the edges.
			var inward := fwd if end == 0 else -fwd
			var right: Vector3 = fr["right"]
			var gate := Basis(right, Vector3.UP, -inward)
			var top := r * 1.15
			var at: Vector3 = fr["o"] + inward * 2.5
			for side in [-1.0, 1.0]:
				_rock_block(Vector3(4.5, top + 7.0, 6.0), gate, at + right * side * (r + 2.25) + Vector3.UP * (top + 7.0) * 0.5 - Vector3.UP * 1.5, rock)
			_rock_block(Vector3(r * 2.0 + 9.0, 6.0, 6.0), gate, at + Vector3.UP * (top + 3.0), rock)

func _rock_block(size: Vector3, basis: Basis, centre: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.transform = Transform3D(basis, centre)
	add_child(mi)
	var body := StaticBody3D.new()
	body.transform = mi.transform
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

func _tunnel_frame(pts: PackedVector2Array, floors: PackedFloat32Array, k: int) -> Dictionary:
	var a := pts[maxi(k - 1, 0)]
	var b := pts[mini(k + 1, pts.size() - 1)]
	var dir := (b - a).normalized()
	var fwd := Vector3(dir.x, 0, dir.y)
	var right := fwd.cross(Vector3.UP).normalized()
	return {"o": Vector3(pts[k].x, floors[k], pts[k].y), "fwd": fwd, "right": right}

# Point m of `ring` around the half-round roof, from the right floor edge over
# the top to the left one.
func _arch_point(fr: Dictionary, r: float, m: int, ring: int) -> Vector3:
	var ang := PI * float(m) / ring
	return fr["o"] + fr["right"] * cos(ang) * r + Vector3.UP * sin(ang) * r * 1.15

func _append_up(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y < 0.0:
		verts.append_array([a, c, b])
	else:
		verts.append_array([a, b, c])

func _crystal_cluster(fr: Dictionary, side: float, r: float, mat: Material, rng: RandomNumberGenerator) -> void:
	var base: Vector3 = fr["o"] + fr["right"] * side * (r - 0.6)
	for n in 3:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = rng.randf_range(0.15, 0.3)
		c.height = rng.randf_range(0.7, 1.6)
		c.radial_segments = 5
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = mat
		mi.position = base + Vector3(rng.randf_range(-0.6, 0.6), c.height * 0.4, rng.randf_range(-0.6, 0.6))
		mi.rotation = Vector3(rng.randf_range(-0.4, 0.4), 0, -side * rng.randf_range(0.2, 0.6))
		add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 0.85, 1.0)
	l.light_energy = 1.6
	l.omni_range = 11.0
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 10.0
	l.position = base + Vector3.UP * 1.2
	add_child(l)

# --- Hazards -----------------------------------------------------------------------

# Lava: one hit and a big pop back out, like Jak's — not instant death.
func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p := _player.global_position
	var surface := lava_surface_at(p.x, p.z)
	if surface == -INF or p.y > surface + 1.4:
		return
	if _player.has_method("take_hit"):
		_player.take_hit(p + Vector3(0, -1, 0))
	if "velocity" in _player:
		_player.velocity.y = lava_damage_pop
	Fx.poof(p, Color(1.0, 0.5, 0.1), 18, 1.4)
