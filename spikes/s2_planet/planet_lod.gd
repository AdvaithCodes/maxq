## Quadtree chunked-LOD cube-sphere planet with camera-relative rendering.
##
## Precision model: every chunk's center is stored in double precision
## (relative to the planet center). Mesh vertices are built in doubles and
## stored relative to the chunk center, so they are small floats. Each frame
## every chunk node is positioned at (chunk_center - camera) computed in
## doubles — the camera itself never leaves the render-space origin. Float32
## never sees a large coordinate, so there is no jitter at the surface of a
## 600 km planet.
class_name PlanetLOD
extends Node3D

const RADIUS := 600_000.0
const HEIGHT_AMP := 4000.0
const SEA_LEVEL := 0.0
const GRID := 16                # quads per chunk side
const MAX_LEVEL := 17           # leaf chunk ~7 m across
const SPLIT_FACTOR := 3.0       # split when camera is closer than size*factor
const BUILDS_PER_FRAME := 4

# Cube faces: [normal, u axis, v axis].
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]

var noise: FastNoiseLite
var material: StandardMaterial3D

var _chunks := {}         # key: String -> MeshInstance3D
var _centers := {}        # key -> DVec3 (chunk center, planet-relative, doubles)
var _center_cache := {}   # key -> DVec3, memoizes _chunk_center (noise calls)
var _desired := {}        # key -> descriptor Array [face, level, ix, iy, center]
var _queued := {}         # key -> true
var _build_queue: Array = []

var built_this_frame := 0
var chunk_count := 0


func _ready() -> void:
	noise = FastNoiseLite.new()
	noise.seed = 1337
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 6
	noise.frequency = 0.8

	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	# Spike shortcut: skip winding-order bookkeeping across 6 cube faces.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _key(face: int, level: int, ix: int, iy: int) -> String:
	return "%d_%d_%d_%d" % [face, level, ix, iy]


func _chunk_size_m(level: int) -> float:
	# Arc length of a chunk: a cube face spans a 90-degree arc.
	return RADIUS * (PI / 2.0) / float(1 << level)


## Direction on the unit sphere for face-local (u, v) in [-1, 1], in doubles.
func _dir(face: int, u: float, v: float) -> DVec3:
	var f: Array = FACES[face]
	var n: Vector3 = f[0]
	var ua: Vector3 = f[1]
	var va: Vector3 = f[2]
	var d := DVec3.new(
		n.x + u * ua.x + v * va.x,
		n.y + u * ua.y + v * va.y,
		n.z + u * ua.z + v * va.z)
	return d.normalized()


## Terrain height above sphere (m). Negative raw noise becomes flat ocean.
func height_at(dir: DVec3) -> float:
	var h := noise.get_noise_3d(dir.x * 2.0, dir.y * 2.0, dir.z * 2.0) * HEIGHT_AMP
	return maxf(h, SEA_LEVEL)


func _raw_height(dir: DVec3) -> float:
	return noise.get_noise_3d(dir.x * 2.0, dir.y * 2.0, dir.z * 2.0) * HEIGHT_AMP


## Surface point (planet-relative, doubles) for face uv.
func _surface_point(face: int, u: float, v: float) -> DVec3:
	var dir := _dir(face, u, v)
	return dir.mul(RADIUS + height_at(dir))


func _chunk_center(face: int, level: int, ix: int, iy: int) -> DVec3:
	var key := _key(face, level, ix, iy)
	var cached: DVec3 = _center_cache.get(key)
	if cached != null:
		return cached
	var n := float(1 << level)
	var u := -1.0 + 2.0 * (float(ix) + 0.5) / n
	var v := -1.0 + 2.0 * (float(iy) + 0.5) / n
	var center := _surface_point(face, u, v)
	# Memoized: recomputing centers (noise sampling) every frame for every
	# visited quadtree node dominated the steady-state LOD cost.
	if _center_cache.size() < 200_000:
		_center_cache[key] = center
	return center


func has_pending_work() -> bool:
	return not _build_queue.is_empty() or built_this_frame > 0


## Recompute the desired leaf set and schedule builds. cam is planet-relative.
func update_lod(cam: DVec3) -> void:
	_desired.clear()
	for face in 6:
		_collect(face, 0, 0, 0, cam)

	# Queue missing chunks.
	for key: String in _desired:
		if not _chunks.has(key) and not _queued.has(key):
			_queued[key] = true
			_build_queue.append(key)

	# Build nearest-first.
	built_this_frame = 0
	if not _build_queue.is_empty():
		_build_queue.sort_custom(func(a: String, b: String) -> bool:
			var da: DVec3 = _desired[a][4] if _desired.has(a) else null
			var db: DVec3 = _desired[b][4] if _desired.has(b) else null
			var la: float = da.sub(cam).length() if da else INF
			var lb: float = db.sub(cam).length() if db else INF
			return la < lb)
		while built_this_frame < BUILDS_PER_FRAME and not _build_queue.is_empty():
			var key: String = _build_queue.pop_front()
			_queued.erase(key)
			if _desired.has(key) and not _chunks.has(key):
				_build_chunk(key, _desired[key])
				built_this_frame += 1

	# Free stale chunks, but only once their replacement coverage is built —
	# otherwise we get transient holes while children are still in the queue.
	for key: String in _chunks.keys():
		if not _desired.has(key) and _covered(key):
			_chunks[key].queue_free()
			_chunks.erase(key)
			_centers.erase(key)
	chunk_count = _chunks.size()


func _collect(face: int, level: int, ix: int, iy: int, cam: DVec3) -> void:
	var center := _chunk_center(face, level, ix, iy)
	var size := _chunk_size_m(level)
	if level < MAX_LEVEL and cam.sub(center).length() < size * SPLIT_FACTOR:
		for cy in 2:
			for cx in 2:
				_collect(face, level + 1, ix * 2 + cx, iy * 2 + cy, cam)
	else:
		_desired[_key(face, level, ix, iy)] = [face, level, ix, iy, center]


static func _parse_key(key: String) -> PackedInt64Array:
	var p := key.split("_")
	return PackedInt64Array([int(p[0]), int(p[1]), int(p[2]), int(p[3])])


## a is a strict ancestor of d?
static func _is_ancestor(a: PackedInt64Array, d: PackedInt64Array) -> bool:
	if a[0] != d[0] or a[1] >= d[1]:
		return false
	var shift: int = d[1] - a[1]
	return (d[2] >> shift) == a[2] and (d[3] >> shift) == a[3]


## True when every desired chunk overlapping `key` has been built.
func _covered(key: String) -> bool:
	var c := _parse_key(key)
	for dkey: String in _desired:
		var d := _parse_key(dkey)
		var overlaps: bool = dkey == key or _is_ancestor(c, d) or _is_ancestor(d, c)
		if overlaps and not _chunks.has(dkey):
			return false
	return true


## Reposition all chunks relative to the camera (both in doubles).
func reposition(cam: DVec3) -> void:
	for key: String in _chunks:
		var center: DVec3 = _centers[key]
		_chunks[key].position = center.sub(cam).to_v3()


func _build_chunk(key: String, desc: Array) -> void:
	var face: int = desc[0]
	var level: int = desc[1]
	var ix: int = desc[2]
	var iy: int = desc[3]
	var center: DVec3 = desc[4]

	var n := float(1 << level)
	var step := 2.0 / n / float(GRID)
	var u0 := -1.0 + 2.0 * float(ix) / n
	var v0 := -1.0 + 2.0 * float(iy) / n
	var side := GRID + 1
	var eside := side + 2  # extended grid with a one-vertex ghost ring

	# Extended positions grid (ghost ring included) built in doubles, so edge
	# normals use centered differences that MATCH the neighboring chunk —
	# one-sided edge normals cause visible lighting seams between chunks.
	var epos := PackedVector3Array()
	epos.resize(eside * eside)
	var eheights := PackedFloat64Array()
	eheights.resize(eside * eside)
	for gy in eside:
		for gx in eside:
			var dir := _dir(face, u0 + step * (gx - 1), v0 + step * (gy - 1))
			var h := height_at(dir)
			var i := gy * eside + gx
			epos[i] = dir.mul(RADIUS + h).sub(center).to_v3()
			eheights[i] = _raw_height(dir)

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var dirs := PackedVector3Array()  # unit dirs (float ok: only guides skirts)
	var normals := PackedVector3Array()
	verts.resize(side * side)
	colors.resize(side * side)
	dirs.resize(side * side)
	normals.resize(side * side)

	for gy in side:
		for gx in side:
			var i := gy * side + gx
			var ei := (gy + 1) * eside + (gx + 1)
			verts[i] = epos[ei]
			colors[i] = _height_color(eheights[ei])
			var dir := _dir(face, u0 + step * gx, v0 + step * gy)
			dirs[i] = dir.to_v3()
			# Centered differences from the extended grid.
			var xa := epos[(gy + 1) * eside + gx]
			var xb := epos[(gy + 1) * eside + (gx + 2)]
			var ya := epos[gy * eside + (gx + 1)]
			var yb := epos[(gy + 2) * eside + (gx + 1)]
			var nrm := (xb - xa).cross(yb - ya).normalized()
			if nrm.dot(dirs[i]) < 0.0:
				nrm = -nrm
			normals[i] = nrm

	var indices := PackedInt32Array()
	for gy in GRID:
		for gx in GRID:
			var a := gy * side + gx
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

	# Skirts: duplicate border verts pulled toward the planet center to hide
	# cracks between neighboring chunks of different LOD.
	var drop := maxf(_chunk_size_m(level) * 0.05, 20.0)
	var border := PackedInt32Array()
	for gx in side:
		border.append(gx)                          # v = v0 edge
		border.append(GRID * side + gx)            # v = v1 edge
	for gy in side:
		border.append(gy * side)                   # u = u0 edge
		border.append(gy * side + GRID)            # u = u1 edge
	var skirt_base := verts.size()
	var skirt_index := {}
	for bi in border:
		if skirt_index.has(bi):
			continue
		skirt_index[bi] = verts.size()
		verts.append(verts[bi] - dirs[bi] * drop)
		normals.append(normals[bi])
		colors.append(colors[bi])
	# Skirt quads along each edge.
	for gx in GRID:
		_add_skirt_quad(indices, skirt_index, gx, gx + 1)
		_add_skirt_quad(indices, skirt_index, GRID * side + gx, GRID * side + gx + 1)
	for gy in GRID:
		_add_skirt_quad(indices, skirt_index, gy * side, (gy + 1) * side)
		_add_skirt_quad(indices, skirt_index, gy * side + GRID, (gy + 1) * side + GRID)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	_chunks[key] = mi
	_centers[key] = center


static func _add_skirt_quad(indices: PackedInt32Array, skirt_index: Dictionary, e0: int, e1: int) -> void:
	var s0: int = skirt_index[e0]
	var s1: int = skirt_index[e1]
	indices.append_array(PackedInt32Array([e0, e1, s0, e1, s1, s0]))


# Smooth height->color ramp. Hard band edges read as posterized/pixelated
# blotches at coarse LOD, so every transition is a smoothstep blend.
const _RAMP: Array = [
	[-4000.0, Color(0.04, 0.10, 0.32)],  # deep ocean
	[-400.0, Color(0.08, 0.22, 0.50)],   # shallow ocean
	[0.0, Color(0.12, 0.32, 0.58)],      # coast water
	[60.0, Color(0.76, 0.72, 0.54)],     # beach
	[500.0, Color(0.27, 0.47, 0.23)],    # lowland
	[1500.0, Color(0.42, 0.42, 0.30)],   # highland
	[2600.0, Color(0.50, 0.46, 0.43)],   # rock
	[3400.0, Color(0.93, 0.93, 0.96)],   # snow
]


func _height_color(h: float) -> Color:
	if h <= _RAMP[0][0]:
		return _RAMP[0][1]
	for i in range(1, _RAMP.size()):
		if h <= _RAMP[i][0]:
			var t: float = (h - _RAMP[i - 1][0]) / (_RAMP[i][0] - _RAMP[i - 1][0])
			return (_RAMP[i - 1][1] as Color).lerp(_RAMP[i][1], smoothstep(0.0, 1.0, t))
	return _RAMP[-1][1]
