## Spike S1 visual demo: on-rails patched-conics orbit + floating origin.
##
## Two view modes (toggle with V):
##  - MAP: scaled-down solar-system view (1 unit = 100 km), orbit trail.
##  - VESSEL: 1:1 scale, floating origin — the vessel is ALWAYS at (0,0,0) and
##    the world (600 km planet, moon) is positioned relative to it. This is the
##    jitter test: at any warp, the vessel must stay rock-steady on screen.
##
## Controls:  , / .  = warp down/up   V = view   +/- = map zoom   R = reset   Esc = quit
extends Node3D

const MAP_SCALE := 1.0e-5  # 1 render unit = 100 km in map view
const WARP_LEVELS: Array[float] = [1.0, 10.0, 100.0, 1000.0, 10_000.0, 100_000.0]
## Vessel view draws distant bodies "scaled space" style: at most this many
## meters away, shrunk to preserve angular size. Keeps the far plane sane
## (a multi-million-unit far plane breaks the light culler / depth precision).
const SCALED_DIST := 30_000.0

const MU_PLANET := 3.5316e12
const R_PLANET := 600_000.0
const MU_MOON := 6.5138e10
const R_MOON := 200_000.0
const MOON_ORBIT_R := 12_000_000.0

var sim: OrbitSim
var planet: CelestialBody
var moon: CelestialBody
var warp_idx := 0
var map_view := true
var map_zoom := 400.0

var _cam: Camera3D
var _planet_mesh: MeshInstance3D
var _moon_mesh: MeshInstance3D
var _vessel_mesh: MeshInstance3D
var _trail_mesh: MeshInstance3D
var _trail_im: ImmediateMesh
var _trail_points := PackedVector3Array()
var _trail_accum := 0.0
var _hud: Label


func _ready() -> void:
	planet = CelestialBody.new("Planet", MU_PLANET, R_PLANET)
	moon = CelestialBody.new("Moon", MU_MOON, R_MOON)
	moon.set_circular_orbit(MU_PLANET, MOON_ORBIT_R, 1.932)
	sim = OrbitSim.new(planet, moon)
	_reset_vessel()

	_cam = Camera3D.new()
	add_child(_cam)

	var sun := DirectionalLight3D.new()
	# Mostly top-down so the map view (looking down -Y) is fully lit.
	sun.rotation_degrees = Vector3(-70.0, 30.0, 0.0)
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.45, 0.5)
	env.environment = e
	add_child(env)

	_planet_mesh = _make_ball(Color(0.3, 0.55, 0.9))
	_moon_mesh = _make_ball(Color(0.65, 0.63, 0.6))
	_vessel_mesh = _make_ball(Color(1.0, 0.5, 0.1))

	_trail_im = ImmediateMesh.new()
	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.mesh = _trail_im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 1.0, 0.4)
	_trail_mesh.material_override = mat
	add_child(_trail_mesh)

	var canvas := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	_hud.add_theme_font_size_override("font_size", 15)
	canvas.add_child(_hud)
	add_child(canvas)


func _make_ball(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radial_segments = 96
	mesh.rings = 48
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
	return mi


func _reset_vessel() -> void:
	# 100 km periapsis, apoapsis at the moon's orbit: a transfer trajectory.
	var rp := R_PLANET + 100_000.0
	var a := (rp + MOON_ORBIT_R) / 2.0
	var vp := sqrt(MU_PLANET * (2.0 / rp - 1.0 / a))
	sim.parent_is_moon = false
	sim.set_state(DVec3.new(rp, 0.0, 0.0), DVec3.new(0.0, 0.0, vp))
	_trail_points.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_PERIOD:
				warp_idx = mini(warp_idx + 1, WARP_LEVELS.size() - 1)
			KEY_COMMA:
				warp_idx = maxi(warp_idx - 1, 0)
			KEY_V:
				map_view = not map_view
				_trail_points.clear()
			KEY_EQUAL, KEY_KP_ADD:
				map_zoom = maxf(map_zoom * 0.75, 30.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				map_zoom = minf(map_zoom * 1.333, 4000.0)
			KEY_R:
				_reset_vessel()
			KEY_ESCAPE:
				get_tree().quit()


func _process(delta: float) -> void:
	var warp: float = WARP_LEVELS[warp_idx]
	sim.advance(sim.t + delta * warp)

	# Trail sampling (map view only).
	_trail_accum += delta
	if map_view and _trail_accum > 0.05:
		_trail_accum = 0.0
		_trail_points.append(sim.world_pos().mul(MAP_SCALE).to_v3())
		if _trail_points.size() > 3000:
			_trail_points = _trail_points.slice(_trail_points.size() - 3000)

	_update_visuals()
	_update_hud(warp)


func _update_visuals() -> void:
	var vessel_wp: DVec3 = sim.world_pos()
	var moon_wp: DVec3 = moon.pos_at(sim.t)

	if map_view:
		# Scaled top-down view centered on the planet. Markers get a minimum
		# on-screen size so nothing vanishes when zoomed out.
		_cam.near = 1.0
		_cam.far = 10_000.0
		_planet_mesh.position = Vector3.ZERO
		_planet_mesh.scale = Vector3.ONE * maxf(R_PLANET * MAP_SCALE * 2.0, map_zoom * 0.03)
		_moon_mesh.position = moon_wp.mul(MAP_SCALE).to_v3()
		_moon_mesh.scale = Vector3.ONE * maxf(R_MOON * MAP_SCALE * 2.0, map_zoom * 0.018)
		_vessel_mesh.position = vessel_wp.mul(MAP_SCALE).to_v3()
		_vessel_mesh.scale = Vector3.ONE * maxf(1.0, map_zoom * 0.012)
		_cam.look_at_from_position(Vector3(0, map_zoom, 0), Vector3.ZERO, Vector3(0, 0, -1))
		_trail_mesh.visible = true
		_rebuild_trail()
	else:
		# 1:1 floating origin: vessel pinned at (0,0,0), world moves around it.
		# Subtraction happens in doubles; only the small result touches floats.
		# Distant bodies use scaled space: drawn nearer and smaller at the same
		# angular size, so the camera far plane stays small.
		_cam.near = 0.1
		_cam.far = SCALED_DIST * 4.0
		_place_scaled(_planet_mesh, DVec3.new().sub(vessel_wp), R_PLANET)
		_place_scaled(_moon_mesh, moon_wp.sub(vessel_wp), R_MOON)
		_vessel_mesh.position = Vector3.ZERO
		_vessel_mesh.scale = Vector3.ONE * 2.0  # a 2 m ball
		_cam.look_at_from_position(Vector3(4, 3, 10), Vector3.ZERO, Vector3.UP)
		_trail_mesh.visible = false


## Position a body mesh in vessel view using scaled-space compression.
func _place_scaled(mi: MeshInstance3D, rel: DVec3, radius: float) -> void:
	var d := rel.length()
	var k := minf(1.0, SCALED_DIST / maxf(d, 1.0))
	mi.position = rel.mul(k).to_v3()
	mi.scale = Vector3.ONE * (radius * 2.0 * k)


func _rebuild_trail() -> void:
	_trail_im.clear_surfaces()
	if _trail_points.size() < 2:
		return
	_trail_im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _trail_points:
		_trail_im.surface_add_vertex(p)
	_trail_im.surface_end()


func _update_hud(warp: float) -> void:
	var days := sim.t / 86400.0
	_hud.text = "MaxQ Spike S1 — orbit + floating origin
t = %.2f days   warp = %.0fx   [,/.] warp  [V] view  [+/-] map zoom  [R] reset
view: %s
SOI: %s   altitude: %.1f km   SOI switches: %d
orbital energy: %.1f J/kg   handoff jump max: %s m
FPS: %d" % [
		days, warp,
		"MAP (1:100000)" if map_view else "VESSEL 1:1 (floating origin — vessel pinned at 0,0,0)",
		sim.parent_name(), sim.altitude() / 1000.0, sim.soi_switch_count,
		Kepler.specific_energy(sim.r, sim.v, sim._parent_mu()),
		String.num_scientific(sim.max_switch_jump),
		Engine.get_frames_per_second(),
	]
