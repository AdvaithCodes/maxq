## Draws the map view: body markers, body orbit lines, the vessel marker, and
## predicted trajectory patches. Everything is drawn relative to a focus point
## (doubles), so render-space coordinates stay small.
class_name OrbitRenderer
extends Node3D

const MAP_SCALE := 1.0e-7  # 1 render unit = 10,000 km
const ORBIT_SAMPLES := 192
const PATCH_COLORS: Array[Color] = [
	Color(0.35, 0.95, 1.0),   # current patch: cyan
	Color(1.0, 0.85, 0.3),    # next: yellow
	Color(1.0, 0.5, 0.9),     # magenta
	Color(1.0, 0.6, 0.3),     # orange
]

var universe: Universe
var _body_meshes := {}        # body -> MeshInstance3D
var _body_orbit_pts := {}     # body -> Array[DVec3] (parent-relative)
var _vessel_mesh: MeshInstance3D
var _lines_mesh: ImmediateMesh
var _node_markers: Array[MeshInstance3D] = []


func setup(p_universe: Universe) -> void:
	universe = p_universe
	var sphere := SphereMesh.new()
	sphere.radial_segments = 48
	sphere.rings = 24

	for body: CelestialBody in universe.bodies:
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = body.color
		mi.material_override = mat
		add_child(mi)
		_body_meshes[body] = mi
		if body.orbit != null:
			_body_orbit_pts[body] = body.orbit.sample_points(ORBIT_SAMPLES)

	_vessel_mesh = MeshInstance3D.new()
	_vessel_mesh.mesh = sphere
	var vmat := StandardMaterial3D.new()
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vmat.albedo_color = Color(0.4, 1.0, 0.45)
	_vessel_mesh.material_override = vmat
	add_child(_vessel_mesh)

	_lines_mesh = ImmediateMesh.new()
	var lines := MeshInstance3D.new()
	lines.mesh = _lines_mesh
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.vertex_color_use_as_albedo = true
	lines.material_override = lmat
	add_child(lines)

	for i in 4:
		var nm := MeshInstance3D.new()
		nm.mesh = sphere
		var nmat := StandardMaterial3D.new()
		nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nmat.albedo_color = Color(0.4, 0.6, 1.0)
		nm.material_override = nmat
		nm.visible = false
		add_child(nm)
		_node_markers.append(nm)


func update_view(t: float, focus: DVec3, vessel: Vessel, patches: Array, cam_dist: float) -> void:
	# Body markers: true size, but never smaller than a visible dot.
	for body: CelestialBody in universe.bodies:
		var mi: MeshInstance3D = _body_meshes[body]
		mi.position = body.world_pos_at(t).sub(focus).mul(MAP_SCALE).to_v3()
		mi.scale = Vector3.ONE * maxf(body.radius * 2.0 * MAP_SCALE, cam_dist * 0.014)

	_vessel_mesh.position = vessel.world_pos().sub(focus).mul(MAP_SCALE).to_v3()
	_vessel_mesh.scale = Vector3.ONE * (cam_dist * 0.009)

	_lines_mesh.clear_surfaces()
	# Body orbit lines (translated to the parent's current position).
	for body: CelestialBody in _body_orbit_pts:
		var parent_wp: DVec3 = body.parent.world_pos_at(t)
		_draw_line(_body_orbit_pts[body], parent_wp, focus, body.color.darkened(0.35), true)

	# Vessel trajectory patches.
	var marker_i := 0
	for pi in patches.size():
		var patch: Dictionary = patches[pi]
		var parent_wp: DVec3 = (patch["parent"] as CelestialBody).world_pos_at(t)
		var color: Color = PATCH_COLORS[mini(pi, PATCH_COLORS.size() - 1)]
		_draw_line(patch["pts"], parent_wp, focus, color, false)
		for m: DVec3 in patch["markers"]:
			if marker_i < _node_markers.size():
				var nm := _node_markers[marker_i]
				nm.visible = true
				nm.position = parent_wp.add(m).sub(focus).mul(MAP_SCALE).to_v3()
				nm.scale = Vector3.ONE * (cam_dist * 0.012)
				marker_i += 1
	for i in range(marker_i, _node_markers.size()):
		_node_markers[i].visible = false


func _draw_line(pts: Array, parent_wp: DVec3, focus: DVec3, color: Color, closed: bool) -> void:
	if pts.size() < 2:
		return
	var off: DVec3 = parent_wp.sub(focus)
	_lines_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_lines_mesh.surface_set_color(color)
	for p: DVec3 in pts:
		_lines_mesh.surface_add_vertex(off.add(p).mul(MAP_SCALE).to_v3())
	if closed:
		_lines_mesh.surface_add_vertex(off.add(pts[0]).mul(MAP_SCALE).to_v3())
	_lines_mesh.surface_end()
