## Max-Q — Phase 1: orbital core. Map view with time warp, patched-conics
## trajectory prediction, and maneuver nodes.
##
## Controls:
##   , / .        time warp down / up (1x .. 1,000,000x)
##   Tab          cycle focus (vessel -> bodies)
##   N            add maneuver node 10 min ahead   X  delete last node
##   U/J          prograde +/-      I/K  normal +/-     O/L  radial +/-
##                (hold Shift for 10x steps)
##   Mouse drag   rotate view       wheel  zoom          Esc  quit
extends Node3D

const WARP_LEVELS: Array[float] = [1.0, 10.0, 100.0, 1000.0, 10_000.0, 100_000.0, 1_000_000.0]
const DV_STEP := 2.0  # m/s per keypress (x10 with Shift)
const PREDICT_INTERVAL := 0.5

var universe: Universe
var vessel: Vessel
var nodes: Array = []
var ut := 0.0
var warp_idx := 0

var renderer: OrbitRenderer
var cam: MapCamera
var hud: Label

var _focus_list: Array = []   # [null(=vessel), body, body, ...]
var _focus_idx := 0
var _patches: Array = []
var _predict_timer := 0.0
var _dirty := true


func _ready() -> void:
	universe = Universe.load_from_json("res://data/system.json")
	vessel = Vessel.new(universe, universe.by_name["Veridia"])
	vessel.set_circular_orbit(100_000.0)

	renderer = OrbitRenderer.new()
	renderer.setup(universe)
	add_child(renderer)

	cam = MapCamera.new()
	add_child(cam)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.03)
	env.environment = e
	add_child(env)

	var canvas := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 14)
	canvas.add_child(hud)
	add_child(canvas)

	_focus_list = [null]
	_focus_list.append_array(universe.bodies)


func _last_node() -> ManeuverNode:
	for i in range(nodes.size() - 1, -1, -1):
		if not nodes[i].executed:
			return nodes[i]
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var step := DV_STEP * (10.0 if event.shift_pressed else 1.0)
	match event.keycode:
		KEY_PERIOD:
			warp_idx = mini(warp_idx + 1, WARP_LEVELS.size() - 1)
		KEY_COMMA:
			warp_idx = maxi(warp_idx - 1, 0)
		KEY_TAB:
			_focus_idx = (_focus_idx + 1) % _focus_list.size()
		KEY_N:
			nodes.append(ManeuverNode.new(ut + 600.0))
			_dirty = true
		KEY_X:
			var n := _last_node()
			if n:
				nodes.erase(n)
				_dirty = true
		KEY_U:
			_adjust_node(step, 0.0, 0.0)
		KEY_J:
			_adjust_node(-step, 0.0, 0.0)
		KEY_I:
			_adjust_node(0.0, step, 0.0)
		KEY_K:
			_adjust_node(0.0, -step, 0.0)
		KEY_O:
			_adjust_node(0.0, 0.0, step)
		KEY_L:
			_adjust_node(0.0, 0.0, -step)
		KEY_ESCAPE:
			get_tree().quit()


func _adjust_node(dp: float, dn: float, dr: float) -> void:
	var n := _last_node()
	if n == null:
		return
	n.prograde += dp
	n.normal += dn
	n.radial += dr
	_dirty = true


func _process(delta: float) -> void:
	var prev_switches := vessel.soi_switch_count
	ut += delta * WARP_LEVELS[warp_idx]
	vessel.advance(ut, nodes)

	# Executed nodes and SOI changes invalidate the prediction.
	for n: ManeuverNode in nodes.duplicate():
		if n.executed:
			nodes.erase(n)
			_dirty = true
	if vessel.soi_switch_count != prev_switches:
		_dirty = true

	_predict_timer -= delta
	if _dirty or _predict_timer <= 0.0:
		_patches = Trajectory.predict(vessel.parent, vessel.r, vessel.v, vessel.t, nodes)
		_predict_timer = PREDICT_INTERVAL
		_dirty = false

	var focus: DVec3 = _focus_pos()
	renderer.update_view(ut, focus, vessel, _patches, cam.dist)
	_update_hud()


func _focus_pos() -> DVec3:
	var f = _focus_list[_focus_idx]
	return vessel.world_pos() if f == null else (f as CelestialBody).world_pos_at(ut)


func _focus_name() -> String:
	var f = _focus_list[_focus_idx]
	return "Vessel" if f == null else (f as CelestialBody).body_name


func _fmt_time(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	return "%dd %02dh %02dm %02ds" % [s / 86400, (s / 3600) % 24, (s / 60) % 60, s % 60]


func _update_hud() -> void:
	var info: Dictionary = Kepler.orbit_info(vessel.r, vessel.v, vessel.parent.mu)
	var ra_txt: String = "%.0f km" % ((info["ra"] - vessel.parent.radius) / 1000.0) \
			if info["ra"] != INF else "escape"
	var per_txt: String = _fmt_time(info["period"]) if info["period"] != INF else "-"

	var node_txt := "none  [N to add]"
	var n := _last_node()
	if n:
		node_txt = "dv %.1f m/s (pro %.1f / nrm %.1f / rad %.1f)  T-%s" % [
			n.dv(), n.prograde, n.normal, n.radial, _fmt_time(maxf(n.t - ut, 0.0))]

	hud.text = "MAX-Q — orbital core (Phase 1)
UT %s   warp %.0fx [,/.]   focus: %s [Tab]   FPS %d
SOI: %s   alt %.1f km   Pe %.1f km   Ap %s   period %s
node: %s
[N] node  [U/J] prograde  [I/K] normal  [O/L] radial  (Shift=10x)  [X] delete" % [
		_fmt_time(ut), WARP_LEVELS[warp_idx], _focus_name(),
		Engine.get_frames_per_second(),
		vessel.parent.body_name, vessel.altitude() / 1000.0,
		(info["rp"] - vessel.parent.radius) / 1000.0, ra_txt, per_txt,
		node_txt,
	]
