## Flight scene: launch pad physics under real central gravity with a floating
## origin (Krakensbane). The physics frame is a non-rotating planet-inertial
## frame whose origin (tracked in doubles) is periodically re-based onto the
## vessel so float32 physics never sees large positions or velocities.
##
## Controls: Space stage · Shift/Ctrl throttle · Z/X full/cut
##           W/S pitch · A/D yaw · Q/E roll · T SAS · P parachute
##           mouse drag orbit camera · Esc back to VAB
extends Node3D

const ATMO_HEIGHT := 70_000.0
const PACK_ALT := 71_000.0     # hand off to rails above the atmosphere
const RHO0 := 1.2              # sea-level density
const SCALE_H := 5600.0        # atmosphere scale height
const CDA_BODY := 0.4          # crude Cd*A per assembly, m^2
const ORIGIN_SHIFT_DIST := 1000.0
const ORIGIN_SHIFT_VEL := 250.0
const TORQUE_PER_KG := 6.0     # control authority
const SAS_DAMP_PER_KG := 4.0

var universe: Universe
var planet: CelestialBody
var fa: FlightAssembly
var origin: DVec3              # planet-centered position of the frame origin
var frame_vel: DVec3           # planet-inertial velocity of the frame
var throttle := 0.0
var sas := true
var t_flight := 0.0
var status_msg := "pre-launch — Space to ignite"
var autotest := false
var _autotest_ok := true
var _autotest_staged := false

var _ground: StaticBody3D
var _cam: Camera3D
var _cam_yaw := 0.5
var _cam_pitch := -0.15
var _cam_dist := 25.0
var _dragging := false
var hud: Label


func _ready() -> void:
	universe = Universe.load_from_json("res://data/system.json")
	planet = universe.by_name["Veridia"]
	var craft: Craft = GameState.current_craft if GameState.current_craft else GameState.default_craft()

	fa = FlightAssembly.new()
	fa.build(craft, self)
	origin = DVec3.new(0.0, planet.radius, 0.0)
	frame_vel = DVec3.new()

	_ground = StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(300, 2, 300)
	gshape.shape = gbox
	_ground.add_child(gshape)
	var gmesh := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(300, 2, 300)
	gmesh.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.35, 0.4, 0.3)
	gmesh.material_override = gmat
	_ground.add_child(gmesh)
	_ground.position = Vector3(0, -1, 0)
	add_child(_ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
	env.environment = e

	_cam = Camera3D.new()
	_cam.far = 2.0e5
	add_child(_cam)

	var canvas := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_font_size_override("font_size", 19)
	canvas.add_child(hud)
	var controls := Label.new()
	controls.add_theme_font_size_override("font_size", 17)
	controls.modulate = Color(1, 1, 1, 0.85)
	controls.text = "[Space] ignite/stage   [Shift/Ctrl] throttle   [Z/X] full/cut   [W/S A/D Q/E] attitude
[T] SAS   [P] parachute   drag=camera   [Esc] back to VAB"
	controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(14, -80)
	canvas.add_child(controls)
	add_child(canvas)

	autotest = "--autotest" in OS.get_cmdline_user_args()
	if autotest:
		# NOTE: do NOT use Engine.time_scale to fast-forward physics tests —
		# it distorts force integration. Run with --fixed-fps 60 instead.
		print("[autotest] flight scene up, craft: ", craft.craft_name)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_cam_dist = maxf(_cam_dist * 0.85, 8.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_cam_dist = minf(_cam_dist * 1.18, 300.0)
	elif event is InputEventMouseMotion and _dragging:
		_cam_yaw -= event.relative.x * 0.006
		_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.006, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				status_msg = fa.do_stage()
			KEY_Z:
				throttle = 1.0
			KEY_X:
				throttle = 0.0
			KEY_T:
				sas = not sas
			KEY_P:
				fa.parachute_deployed = true
				status_msg = "parachute armed"
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://vab.tscn")


func _physics_process(delta: float) -> void:
	t_flight += delta

	# Throttle.
	if Input.is_key_pressed(KEY_SHIFT):
		throttle = minf(throttle + delta * 0.6, 1.0)
	if Input.is_key_pressed(KEY_CTRL):
		throttle = maxf(throttle - delta * 0.6, 0.0)

	# Attitude control on the pod's assembly.
	var ctrl := fa.control_body()
	var pitch_in := (1.0 if Input.is_key_pressed(KEY_W) else 0.0) \
			- (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	var yaw_in := (1.0 if Input.is_key_pressed(KEY_A) else 0.0) - (1.0 if Input.is_key_pressed(KEY_D) else 0.0)
	var roll_in := (1.0 if Input.is_key_pressed(KEY_Q) else 0.0) - (1.0 if Input.is_key_pressed(KEY_E) else 0.0)
	var m_ctl := fa.attached_mass()
	if pitch_in != 0.0 or yaw_in != 0.0 or roll_in != 0.0:
		var tq: Vector3 = ctrl.global_transform.basis * Vector3(pitch_in, roll_in, yaw_in)
		ctrl.apply_torque(tq * TORQUE_PER_KG * m_ctl)
	elif sas:
		ctrl.apply_torque(-ctrl.angular_velocity * SAS_DAMP_PER_KG * m_ctl)

	# Per-body gravity and drag (world state = origin/frame_vel + local).
	for body: RigidBody3D in fa.bodies:
		var wp: DVec3 = origin.add(DVec3.new(body.position.x, body.position.y, body.position.z))
		var rm := wp.length()
		var g_acc := planet.mu / (rm * rm)
		var g_dir := wp.mul(-1.0 / rm)
		body.apply_central_force(g_dir.to_v3() * (g_acc * body.mass))

		var h := rm - planet.radius
		if h < ATMO_HEIGHT:
			var vair: Vector3 = frame_vel.to_v3() + body.linear_velocity
			var speed := vair.length()
			if speed > 0.1:
				var rho := RHO0 * exp(-maxf(h, 0.0) / SCALE_H)
				var cda := CDA_BODY
				if body == fa.control_body() and fa.parachute_deployed \
						and h < 2000.0 and speed < 300.0:
					cda += fa.parachute_area
				var fdrag: float = minf(0.5 * rho * speed * speed * cda, body.mass * 400.0)
				body.apply_central_force(-vair / speed * fdrag)

	fa.apply_thrust(throttle, delta)

	_krakensbane(delta)
	_check_pack_to_rails()
	if autotest:
		_autotest_tick()


## Re-base the frame origin/velocity onto the pod so physics floats stay small.
## CRITICAL: the frame itself moves at frame_vel, so the origin must be
## integrated every tick — forgetting this freezes the world bookkeeping the
## moment the first velocity rebase happens.
func _krakensbane(delta: float) -> void:
	origin = origin.add(frame_vel.mul(delta))

	var pod := fa.control_body()
	var p := pod.position
	if p.length() > ORIGIN_SHIFT_DIST:
		origin = origin.add(DVec3.new(p.x, p.y, p.z))
		for body: RigidBody3D in fa.bodies:
			body.position -= p
		if _ground != null:
			_ground.position -= p
	var v := pod.linear_velocity
	if v.length() > ORIGIN_SHIFT_VEL:
		frame_vel = frame_vel.add(DVec3.new(v.x, v.y, v.z))
		for body: RigidBody3D in fa.bodies:
			body.linear_velocity -= v
		# A static pad cannot follow a moving frame; drop it if still around.
		if _ground != null:
			_ground.queue_free()
			_ground = null

	# The pad only matters near the pad.
	if _ground != null and _altitude() > 5000.0:
		_ground.queue_free()
		_ground = null


func _altitude() -> float:
	var pod := fa.control_body()
	return origin.add(DVec3.new(pod.position.x, pod.position.y, pod.position.z)).length() - planet.radius


func _pod_world_state() -> Array:
	var pod := fa.control_body()
	var r: DVec3 = origin.add(DVec3.new(pod.position.x, pod.position.y, pod.position.z))
	var v: DVec3 = frame_vel.add(DVec3.new(
			pod.linear_velocity.x, pod.linear_velocity.y, pod.linear_velocity.z))
	return [r, v]


func _check_pack_to_rails() -> void:
	if _altitude() < PACK_ALT:
		return
	var state := _pod_world_state()
	GameState.pending_vessel = {"parent": "Veridia", "r": state[0], "v": state[1]}
	if autotest:
		var info: Dictionary = Kepler.orbit_info(state[0], state[1], planet.mu)
		print("[autotest] packed to rails: Pe %.0f km  Ap %s" % [
			(info["rp"] - planet.radius) / 1000.0,
			("%.0f km" % ((info["ra"] - planet.radius) / 1000.0)) if info["ra"] != INF else "esc"])
		_autotest_finish()
		return
	get_tree().change_scene_to_file("res://main.tscn")


func _process(_delta: float) -> void:
	var pod := fa.control_body()
	var basis := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0))
	_cam.position = pod.position + basis * Vector3(0, 0, _cam_dist)
	_cam.transform.basis = basis
	_update_hud()


func _update_hud() -> void:
	var state := _pod_world_state()
	var info: Dictionary = Kepler.orbit_info(state[0], state[1], planet.mu)
	var speed: float = state[1].length()
	var up: DVec3 = state[0].normalized()
	var pod_up: Vector3 = fa.control_body().global_transform.basis.y
	var pitch := 90.0 - rad_to_deg(acos(clampf(pod_up.dot(up.to_v3()), -1.0, 1.0)))
	var twr := fa.current_thrust(throttle) / (fa.attached_mass() * 9.81)
	var ra_txt: String = "%.1f km" % ((info["ra"] - planet.radius) / 1000.0) \
			if info["ra"] != INF else "escape"

	hud.text = "MAX-Q FLIGHT   T+%s   %s
alt %.2f km   speed %.0f m/s   pitch %.0f deg
Ap %s   Pe %.1f km
throttle %3.0f%%   TWR %.2f   stage fuel %3.0f%%   SAS %s" % [
		"%d:%02d" % [int(t_flight) / 60, int(t_flight) % 60], status_msg,
		_altitude() / 1000.0, speed, pitch,
		ra_txt, (info["rp"] - planet.radius) / 1000.0,
		throttle * 100.0, twr, fa.current_stage_fuel_fraction() * 100.0,
		"on" if sas else "off",
	]


## ---- headless autotest ----
## Run: godot --headless --fixed-fps 240 --path . res://flight.tscn -- --autotest
var _telemetry_next := 0.0


func _autotest_tick() -> void:
	if t_flight >= _telemetry_next:
		_telemetry_next += 10.0
		var state := _pod_world_state()
		var gap: float = (fa.bodies[1].position - fa.bodies[0].position).length() \
				if fa.bodies.size() > 1 else 0.0
		print("[telemetry] t=%5.1f alt=%8.0f v=%6.1f up_y=%.3f gap=%.2f thr=%.1f" % [
			t_flight, _altitude(), state[1].length(),
			fa.bodies[0].global_transform.basis.y.y, gap, throttle])
	if t_flight > 1.0 and not fa.any_ignited:
		throttle = 1.0
		print("[autotest] ignition, t=%.1f" % t_flight)
		print("[autotest] " + fa.do_stage())
	if fa.any_ignited and not _autotest_staged and fa.fuel[fa.stage] <= 0.0:
		_autotest_staged = true
		print("[autotest] booster empty at t=%.1f, alt %.0f m -> staging" % [t_flight, _altitude()])
		print("[autotest] " + fa.do_stage())
	if t_flight > 5.0 and _altitude() < 1.0 and not fa.any_ignited:
		_autotest_ok = false
		_autotest_finish()
	if t_flight > 600.0:
		print("[autotest] TIMEOUT without reaching pack altitude, alt %.0f m" % _altitude())
		_autotest_ok = false
		_autotest_finish()


func _autotest_finish() -> void:
	print("[autotest] %s" % ("PASS" if _autotest_ok else "FAIL"))
	get_tree().quit(0 if _autotest_ok else 1)
