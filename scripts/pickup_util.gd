class_name PickupUtil
extends RefCounted
# Shared helper for dropped pickups (coins, Exotic Matter).
#
# Heads die wherever they're standing, including inside a building footprint, and
# a pickup's landing spot comes from height_at() — which is the STREET height and
# knows nothing about walls. So a drop can settle inside a building, where nobody
# can reach it: not the player, and not Biscuit, who would walk at it for ever.
#
# "Inside" is detected by looking for a ceiling: streets and island terrain have
# open sky above them, building interiors don't. (Tree canopies aren't colliders
# — only trunks and rocks are — so foliage doesn't trigger this.)

const CEILING_PROBE := 80.0     # how far up to look for a roof
const RING_STEP := 3.0          # metres between search rings
const RINGS := 14               # reach far enough to escape a whole city block


# City buildings are SOLID BoxShape3D bodies, so a drop in one is inside a convex
# shape. A point query answers that directly — an upward ray does not, because
# PhysicsRayQueryParameters3D.hit_from_inside defaults to false and a ray that
# starts inside a shape reports nothing, which is precisely this case.
static func inside_solid(world: World3D, pos: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos
	q.collision_mask = 1
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return world.direct_space_state.intersect_point(q, 1).size() > 0


# Kept for hollow interiors, where the point query finds nothing but there is a
# roof overhead. hit_from_inside matters here too.
static func has_ceiling(world: World3D, pos: Vector3) -> bool:
	var from := pos + Vector3.UP * 0.4
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * CEILING_PROBE)
	q.collision_mask = 1
	q.collide_with_areas = false
	q.hit_from_inside = true
	return not world.direct_space_state.intersect_ray(q).is_empty()


static func unreachable(world: World3D, pos: Vector3) -> bool:
	return inside_solid(world, pos) or has_ceiling(world, pos)


# If `node` has landed under a roof, walk it out to the nearest open-sky spot on
# walkable ground. Returns true if it was moved.
static func nudge_into_the_open(node: Node3D, ground: Node, rest_height: float) -> bool:
	var world := node.get_world_3d()
	if not unreachable(world, node.global_position):
		return false
	for ring in range(1, RINGS + 1):
		var r: float = ring * RING_STEP
		for i in 8:
			var a: float = (TAU / 8.0) * i
			var p := Vector3(node.global_position.x + cos(a) * r, 0.0,
				node.global_position.z + sin(a) * r)
			if ground != null and ground.has_method("is_walkable") and not ground.is_walkable(p.x, p.z):
				continue
			if ground != null and ground.has_method("height_at"):
				p.y = ground.height_at(p.x, p.z) + rest_height
			else:
				p.y = node.global_position.y
			if not unreachable(world, p):
				node.global_position = p
				return true
	return false
