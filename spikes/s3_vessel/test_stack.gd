## Spike S3: Jolt physics acceptance test — a 50-part rocket "stack" of jointed
## rigid bodies. Runs headless or windowed and self-reports PASS/FAIL:
##   godot --headless --path spikes/s3_vessel
##
## Phases:
##   A [0-5 s)   sit on the pad          -> top part must not drift (no wobble)
##   B [5-9 s)   thrust from bottom part -> stack must stay aligned (no noodle)
##   C [9 s]     stage: middle joint removed under load
##   D (9-13 s]  free flight + falling   -> no NaN/explosion
extends Node3D

const PART_COUNT := 50
const PART_MASS := 500.0     # kg
const PART_HEIGHT := 2.0     # m
const PART_RADIUS := 0.625   # m
const THRUST_FACTOR := 1.3   # thrust = 1.3x total weight
const GRAVITY := 9.8

## true  = parts welded into stage assemblies (one rigid body per stage,
##         compound collision shapes, joints only at decoupler interfaces).
##         This is the design the game will use.
## false = every part its own rigid body in a 49-joint chain. Kept as a
##         reproduction of the "noodle rocket" failure mode: an iterative
##         solver cannot keep a long jointed chain stiff under compression
##         (buckles >160 deg). Do not ship this configuration.
const WELDED := true

## Which parts belong to which stage (bottom to top).
const STAGE_SPLITS: Array[int] = [17, 34]

const PAD_DRIFT_LIMIT := 0.05   # m, phase A
const TILT_LIMIT_DEG := 5.0     # deg, phase B
const SPEED_SANITY := 1000.0    # m/s, phase D

var parts: Array[RigidBody3D] = []
var joints: Array[Generic6DOFJoint3D] = []
var t := 0.0
var staged := false
var failures := 0

var max_pad_drift := 0.0
var max_tilt_deg := 0.0
var sane := true
var phys_time_accum := 0.0
var phys_samples := 0
var top_start_xz := Vector2.ZERO


func _ready() -> void:
	print("=== Spike S3: 50-part Jolt stack ===")
	print("physics engine: ", ProjectSettings.get_setting("physics/3d/physics_engine"))

	# Pad.
	var ground := StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(200, 2, 200)
	gshape.shape = gbox
	ground.add_child(gshape)
	ground.position = Vector3(0, -1, 0)
	add_child(ground)

	# Group parts into stages: [0, split0), [split0, split1), [split1, end).
	var stage_ranges: Array[Vector2i] = []
	if WELDED:
		var prev := 0
		for s in STAGE_SPLITS:
			stage_ranges.append(Vector2i(prev, s))
			prev = s
		stage_ranges.append(Vector2i(prev, PART_COUNT))
	else:
		for i in PART_COUNT:
			stage_ranges.append(Vector2i(i, i + 1))

	var mesh := CylinderMesh.new()
	mesh.top_radius = PART_RADIUS
	mesh.bottom_radius = PART_RADIUS
	mesh.height = PART_HEIGHT

	# One rigid body per stage; each part contributes a collision shape and a
	# mesh at its local offset within the stage.
	for rng in stage_ranges:
		var count := rng.y - rng.x
		var center_y := PART_HEIGHT * 0.5 + PART_HEIGHT * (float(rng.x + rng.y - 1) / 2.0)
		var body := RigidBody3D.new()
		body.mass = PART_MASS * count
		body.can_sleep = false
		body.position = Vector3(0, center_y, 0)
		for i in range(rng.x, rng.y):
			var local_y := PART_HEIGHT * 0.5 + PART_HEIGHT * i - center_y
			var cshape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = PART_RADIUS
			cyl.height = PART_HEIGHT
			cshape.shape = cyl
			cshape.position = Vector3(0, local_y, 0)
			body.add_child(cshape)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(0, local_y, 0)
			body.add_child(mi)
		add_child(body)
		parts.append(body)

	# Attached assemblies must not collide with each other: contact impulses
	# fight the joints and cause wobble/buckling (KSP does the same).
	for i in parts.size() - 1:
		parts[i].add_collision_exception_with(parts[i + 1])

	# Joints only at functional interfaces (decouplers).
	for i in parts.size() - 1:
		var boundary_part := (STAGE_SPLITS[i] if WELDED else i + 1)
		var joint := Generic6DOFJoint3D.new()
		joint.position = Vector3(0, PART_HEIGHT * boundary_part, 0)
		add_child(joint)
		# Default 6DOF limits are all locked (0..0) -> a rigid connection.
		joint.node_a = parts[i].get_path()
		joint.node_b = parts[i + 1].get_path()
		joints.append(joint)

	top_start_xz = _xz(parts[parts.size() - 1].global_position)
	var cam := Camera3D.new()
	cam.position = Vector3(60, 60, 120)
	add_child(cam)
	cam.look_at(Vector3(0, 50, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _physics_process(delta: float) -> void:
	t += delta
	phys_time_accum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	phys_samples += 1

	var top := parts[parts.size() - 1]
	var bottom := parts[0]

	if t < 5.0:
		# Phase A: pad stability.
		max_pad_drift = maxf(max_pad_drift, (_xz(top.global_position) - top_start_xz).length())
	elif t < 9.0:
		# Phase B: thrust, alignment check.
		var thrust := THRUST_FACTOR * PART_COUNT * PART_MASS * GRAVITY
		bottom.apply_central_force(Vector3.UP * thrust)
		var axis := (top.global_position - bottom.global_position).normalized()
		max_tilt_deg = maxf(max_tilt_deg, rad_to_deg(acos(clampf(axis.dot(Vector3.UP), -1.0, 1.0))))
	elif not staged:
		# Phase C: stage — cut the middle joint under residual motion.
		staged = true
		joints[joints.size() / 2].queue_free()
		print("  staged at t=%.2f s (altitude of bottom: %.1f m)" % [t, bottom.global_position.y])
	elif t < 13.0:
		# Phase D: sanity.
		for p in parts:
			var pos := p.global_position
			if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)) \
					or p.linear_velocity.length() > SPEED_SANITY:
				sane = false
	else:
		_report()


func _check(cond: bool, label: String, detail: String) -> void:
	if cond:
		print("  PASS  %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _report() -> void:
	set_physics_process(false)
	var avg_phys_ms := phys_time_accum / float(phys_samples) * 1000.0
	print("\n[results]")
	_check(max_pad_drift < PAD_DRIFT_LIMIT, "pad stability: top drift < %.2f m" % PAD_DRIFT_LIMIT,
			"(max %.4f m)" % max_pad_drift)
	_check(max_tilt_deg < TILT_LIMIT_DEG, "thrust alignment: tilt < %.0f deg" % TILT_LIMIT_DEG,
			"(max %.3f deg)" % max_tilt_deg)
	_check(sane, "post-staging sanity (finite, < %.0f m/s)" % SPEED_SANITY, "")
	print("  INFO  avg physics time per frame: %.3f ms (budget: 4 ms)" % avg_phys_ms)
	print("\n%s" % ("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)
