## Headless tests for the welded-assembly flight build (ADR-004).
## Run: godot --headless --path . --script res://tests/test_flight_assembly.gd
extends SceneTree

var _failures := 0


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _initialize() -> void:
	print("=== Max-Q flight assembly tests ===")
	var catalog := PartDef.load_catalog()
	var craft := Craft.new()
	var pod := craft.add_part(catalog["pod_mk1"])
	craft.add_part(catalog["parachute_mk1"], pod)
	var t1 := craft.add_part(catalog["tank_s"], pod)
	var e1 := craft.add_part(catalog["engine_sparrow"], t1)
	var d := craft.add_part(catalog["decoupler_s"], e1)
	var t2 := craft.add_part(catalog["tank_l"], d)
	craft.add_part(catalog["engine_kestrel"], t2)

	var root_node := Node3D.new()
	get_root().add_child(root_node)
	var fa := FlightAssembly.new()
	fa.build(craft, root_node)

	_check(fa.bodies.size() == 2, "2 welded bodies", "(%d)" % fa.bodies.size())
	_check(fa.joints.size() == 1, "1 decoupler joint", "(%d)" % fa.joints.size())
	# Bottom group: decoupler 50 + tank_l 1000+8000 + kestrel 1200 = 10250.
	_check(absf(fa.bodies[0].mass - 10_250.0) < 0.01, "bottom assembly mass",
			"(%.0f kg)" % fa.bodies[0].mass)
	# Top group: pod 800 + chute 100 + tank_s 250+2000 + sparrow 500 = 3650.
	_check(absf(fa.bodies[1].mass - 3_650.0) < 0.01, "top assembly mass",
			"(%.0f kg)" % fa.bodies[1].mass)
	_check(fa.control_body() == fa.bodies[1], "pod assembly is control body")
	_check(absf(fa.attached_mass() - 13_900.0) < 0.01, "attached mass = full craft")

	# Lowest collision point must clear the ground plane placement (y >= ~1).
	var lowest := INF
	for body: RigidBody3D in fa.bodies:
		for c in body.get_children():
			if c is CollisionShape3D:
				var cyl: CylinderShape3D = c.shape
				lowest = minf(lowest, body.position.y + c.position.y - cyl.height * 0.5)
	_check(absf(lowest - 1.0) < 0.01, "stack sits at clearance height",
			"(lowest %.2f m)" % lowest)

	# Staging sequence.
	_check(fa.do_stage() == "ignition!", "first stage ignites")
	_check(fa.ignited[0] and not fa.ignited[1], "only bottom engines lit")
	fa.fuel[0] = 0.0
	_check(fa.do_stage() == "stage separation", "second press separates")
	_check(fa.detached[0] and fa.ignited[1], "booster detached, upper lit")
	_check(absf(fa.attached_mass() - 3_650.0) < 0.01, "attached mass after sep",
			"(%.0f kg)" % fa.attached_mass())

	# Thrust drains fuel and mass.
	var m0: float = fa.bodies[1].mass
	fa.apply_thrust(1.0, 1.0)  # 1 s at full throttle
	var flow: float = 60_000.0 / (320.0 * 9.80665)
	_check(absf((m0 - fa.bodies[1].mass) - flow) < 0.01, "fuel flow correct",
			"(%.2f kg/s)" % (m0 - fa.bodies[1].mass))

	if _failures == 0:
		print("\nALL TESTS PASSED")
	else:
		print("\n%d TEST(S) FAILED" % _failures)
	quit(0 if _failures == 0 else 1)
