## Max-Q — Phase 1: orbital core. Map view with time warp, patched-conics
## trajectory prediction, and maneuver nodes.
##
## Controls:
##   , / .        time warp down / up (1x .. 1,000,000x; auto-limited near events)
##   Tab          cycle focus (vessel -> bodies)
##   N            add maneuver node 10 min ahead   X  delete last node
##   U/J          prograde +/-      I/K  normal +/-     O/L  radial +/-
##   Y/H          node later/earlier                Z  warp to node
##                (hold Shift for 10x steps)
##   Mouse drag   rotate view       wheel  zoom          Esc  quit
extends Node3D

const WARP_LEVELS: Array[float] = [1.0, 10.0, 100.0, 1000.0, 10_000.0, 100_000.0, 1_000_000.0]
const DV_STEP := 2.0        # m/s per keypress (x10 with Shift)
const TIME_STEP := 15.0     # s of node-time shift per keypress (x10 with Shift)
const PREDICT_INTERVAL := 0.5
## A warp level is allowed only if the next event (node / SOI change) is more
## than EVENT_MARGIN * level seconds away — so warp ramps down automatically.
const EVENT_MARGIN := 5.0
const WARP_TO_LEAD := 30.0  # arrive this many seconds before the node

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
var _approaches: Array = []
var _predict_timer := 0.0
var _dirty := true
var _warp_to := -1.0          # target UT for warp-to-node (-1 = inactive)
var _warp_limited := false


func _ready() -> void:
	universe = Universe.load_from_json("res://data/system.json")
	if not GameState.pending_vessel.is_empty():
		# Arriving from the flight scene: adopt the packed-to-rails state.
		var pv: Dictionary = GameState.pending_vessel
		GameState.pending_vessel = {}
		vessel = Vessel.new(universe, universe.by_name[pv["parent"]])
		vessel.set_state(pv["r"], pv["v"])
	else:
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
	hud.position = Vector2(14, 10)
	hud.add_theme_font_size_override("font_size", 19)
	canvas.add_child(hud)

	var controls := Label.new()
	controls.add_theme_font_size_override("font_size", 17)
	controls.modulate = Color(1.0, 1.0, 1.0, 0.85)
	controls.text = "[,/.] time warp    [Tab] focus    [N] add node    [X] delete node    [Z] warp to node
[U/J] prograde +/-    [I/K] normal +/-    [O/L] radial +/-    [Y/H] node later/earlier    (Shift = 10x)
mouse drag = rotate    wheel = zoom    [B] VAB    [Esc] quit"
	controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(14, -110)
	controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	canvas.add_child(controls)
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
	var tstep := TIME_STEP * (10.0 if event.shift_pressed else 1.0)
	match event.keycode:
		KEY_PERIOD:
			warp_idx = mini(warp_idx + 1, WARP_LEVELS.size() - 1)
			_warp_to = -1.0
		KEY_COMMA:
			warp_idx = maxi(warp_idx - 1, 0)
			_warp_to = -1.0
		KEY_Z:
			var zn := _last_node()
			if zn:
				_warp_to = zn.t - WARP_TO_LEAD
		KEY_Y:
			_shift_node_time(tstep)
		KEY_H:
			_shift_node_time(-tstep)
		KEY_TAB:
			_focus_idx = (_focus_idx + 1) % _focus_list.size()
		KEY_N:
			# Start with a visible prograde nudge so the new node's effect on
			# the trajectory is immediately obvious.
			var new_node := ManeuverNode.new(ut + 600.0)
			new_node.prograde = 10.0
			nodes.append(new_node)
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
		KEY_B:
			get_tree().change_scene_to_file("res://vab.tscn")
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


func _shift_node_time(dt: float) -> void:
	var n := _last_node()
	if n == null:
		return
	n.t = maxf(n.t + dt, ut + 5.0)
	_dirty = true


## Next upcoming event: nearest unexecuted node or predicted SOI change.
func _next_event_time() -> float:
	var e := INF
	for n: ManeuverNode in nodes:
		if not n.executed and n.t > ut:
			e = minf(e, n.t)
	# A multi-patch prediction means the current patch ends at an SOI change.
	if _patches.size() > 1:
		e = minf(e, _patches[0]["t_end"])
	return e


## Largest warp level that keeps the next event comfortably far away.
func _warp_limit() -> float:
	var dt_event := _next_event_time() - ut
	if dt_event == INF:
		return WARP_LEVELS[-1]
	var allowed: float = WARP_LEVELS[0]
	for level: float in WARP_LEVELS:
		if dt_event > level * EVENT_MARGIN:
			allowed = level
	return allowed


func _process(delta: float) -> void:
	var prev_switches := vessel.soi_switch_count

	# Atmosphere entry with a live craft: hand back to the flight scene.
	if not GameState.flight_snapshot.is_empty() \
			and vessel.parent.body_name == "Veridia" \
			and vessel.altitude() < 68_000.0:
		GameState.pending_flight_state = {"r": vessel.r.copy(), "v": vessel.v.copy()}
		get_tree().change_scene_to_file("res://flight.tscn")
		return

	var limit := _warp_limit()
	var warp: float = WARP_LEVELS[warp_idx]
	if _warp_to > ut:
		warp = limit  # auto-pilot the warp up to whatever is safe
	elif _warp_to > 0.0:
		_warp_to = -1.0  # arrived: drop to real time
		warp_idx = 0
		warp = WARP_LEVELS[0]
	var effective := minf(warp, limit)
	_warp_limited = effective < warp

	ut += delta * effective
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
		var result := Trajectory.predict(vessel.parent, vessel.r, vessel.v, vessel.t, nodes)
		_patches = result["patches"]
		_approaches = result["approaches"]
		_predict_timer = PREDICT_INTERVAL
		_dirty = false

	var focus: DVec3 = _focus_pos()
	renderer.update_view(ut, focus, vessel, _patches, _approaches, cam.dist)
	_update_hud(effective)


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


func _update_hud(effective_warp: float) -> void:
	var info: Dictionary = Kepler.orbit_info(vessel.r, vessel.v, vessel.parent.mu)
	var ra_txt: String = "%.0f km" % ((info["ra"] - vessel.parent.radius) / 1000.0) \
			if info["ra"] != INF else "escape"
	var per_txt: String = _fmt_time(info["period"]) if info["period"] != INF else "-"

	var warp_txt := "%.0fx" % effective_warp
	if _warp_to > 0.0:
		warp_txt += "  (warping to node)"
	elif _warp_limited:
		warp_txt += "  (auto-limited: event ahead)"

	var node_txt := "none  [N to add]"
	var n := _last_node()
	if n:
		node_txt = "dv %.1f m/s (pro %.1f / nrm %.1f / rad %.1f)  T-%s" % [
			n.dv(), n.prograde, n.normal, n.radial, _fmt_time(maxf(n.t - ut, 0.0))]

	var approach_txt := ""
	if not _approaches.is_empty():
		var ap: Dictionary = _approaches[0]
		approach_txt = "\nclosest approach: %s  %.0f km  (T-%s)" % [
			(ap["body"] as CelestialBody).body_name, ap["dist"] / 1000.0,
			_fmt_time(maxf(ap["t"] - ut, 0.0))]

	hud.text = "MAX-Q — orbital core (Phase 1)
UT %s   warp %s   focus: %s   FPS %d
SOI: %s   alt %.1f km   Pe %.1f km   Ap %s   period %s
node: %s%s" % [
		_fmt_time(ut), warp_txt, _focus_name(),
		Engine.get_frames_per_second(),
		vessel.parent.body_name, vessel.altitude() / 1000.0,
		(info["rp"] - vessel.parent.radius) / 1000.0, ra_txt, per_txt,
		node_txt, approach_txt,
	]
