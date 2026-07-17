## Spike S2: fly from a 100 km orbit down to the surface of a 600 km planet.
## Acceptance: no LOD cracks, no jitter at the surface, >=60 fps on the M4,
## >=30 fps on the Intel machines (Compatibility renderer).
##
## Controls: click = capture mouse, WASD + QE = fly, wheel = speed,
##           F = auto-speed toggle, Esc = release mouse / quit
extends Node3D

var planet: PlanetLOD
var cam: FlyCam
var hud: Label
var _last_lod_pos: DVec3 = DVec3.new(INF, INF, INF)


func _ready() -> void:
	planet = PlanetLOD.new()
	add_child(planet)

	cam = FlyCam.new()
	add_child(cam)
	# Start at 100 km altitude, looking along the horizon.
	cam.dpos = DVec3.new(0.0, 0.0, PlanetLOD.RADIUS + 100_000.0)
	cam.rotation = Vector3(0, 0, 0)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 25.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.4
	env.environment = e
	add_child(env)

	var canvas := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 15)
	canvas.add_child(hud)
	add_child(canvas)


func _process(delta: float) -> void:
	var altitude := cam.dpos.length() - PlanetLOD.RADIUS
	cam.fly(delta, altitude)
	cam.update_planes(altitude)
	# Skip the LOD pass when the camera barely moved and nothing is pending.
	var moved: float = cam.dpos.sub(_last_lod_pos).length()
	if moved > maxf(1.0, absf(altitude) * 0.001) or planet.has_pending_work():
		planet.update_lod(cam.dpos)
		_last_lod_pos = cam.dpos.copy()
	planet.reposition(cam.dpos)

	hud.text = "MaxQ Spike S2 — planet LOD (600 km radius)
click=mouse  WASD/QE=fly  wheel=speed  F=auto-speed  Esc=quit
FPS: %d
altitude: %.2f km   speed: %.0f m/s (%s)
chunks: %d   built this frame: %d" % [
		Engine.get_frames_per_second(),
		altitude / 1000.0,
		cam.speed, "auto" if cam.auto_speed else "manual",
		planet.chunk_count, planet.built_this_frame,
	]
