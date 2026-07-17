## Headless tests for the Phase 1 sim layer.
## Run: godot --headless --path . --script res://tests/test_sim.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	print("=== Max-Q sim tests ===")
	_test_universe_load()
	_test_elements_consistency()
	_test_hierarchy_positions()
	_test_vessel_stable_orbit()
	_test_node_execution()
	_test_transfer_to_moon()
	_test_closest_approach()

	if _failures == 0:
		print("\nALL TESTS PASSED")
	else:
		print("\n%d TEST(S) FAILED" % _failures)
	quit(0 if _failures == 0 else 1)


func _sci(x: float) -> String:
	return String.num_scientific(x)


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _load() -> Universe:
	return Universe.load_from_json("res://data/system.json")


func _test_universe_load() -> void:
	print("\n[universe loads]")
	var u := _load()
	_check(u.root != null and u.root.body_name == "Helion", "root is Helion")
	_check(u.bodies.size() == 6, "6 bodies", "(%d)" % u.bodies.size())
	var veridia: CelestialBody = u.by_name["Veridia"]
	_check(veridia.children.size() == 2, "Veridia has 2 moons")
	_check(veridia.soi > 8.0e7 and veridia.soi < 1.2e8,
			"Veridia SOI plausible", "(%.0f km)" % (veridia.soi / 1000.0))


## OrbitElements analytic state must agree with universal-variable propagation.
func _test_elements_consistency() -> void:
	print("\n[elements vs propagator consistency]")
	var u := _load()
	var rusk: CelestialBody = u.by_name["Rusk"]  # eccentric + inclined
	var r0 := rusk.local_pos_at(0.0)
	var v0 := rusk.local_vel_at(0.0)
	var dt := 5.0e6
	var out: Array = Kepler.propagate(r0, v0, u.root.mu, dt)
	var pos_err: float = out[0].sub(rusk.local_pos_at(dt)).length()
	var vel_err: float = out[1].sub(rusk.local_vel_at(dt)).length()
	_check(pos_err < 100.0, "position agrees within 100 m over 58 days",
			"(err %.4f m)" % pos_err)
	_check(vel_err < 0.01, "velocity agrees within 1 cm/s", "(err %s)" % _sci(vel_err))


func _test_hierarchy_positions() -> void:
	print("\n[hierarchy world positions]")
	var u := _load()
	var cinder: CelestialBody = u.by_name["Cinder"]
	var veridia: CelestialBody = u.by_name["Veridia"]
	var t := 12_345.0
	var expected: DVec3 = veridia.world_pos_at(t).add(cinder.local_pos_at(t))
	var err: float = cinder.world_pos_at(t).sub(expected).length()
	_check(err < 1.0e-6, "moon world pos = planet + local", "(err %s m)" % _sci(err))
	var d: float = cinder.world_pos_at(t).sub(veridia.world_pos_at(t)).length()
	_check(absf(d - 1.2e7) < 1.0, "moon distance = orbit radius", "(%.1f km)" % (d / 1000.0))


func _test_vessel_stable_orbit() -> void:
	print("\n[vessel: 100 km orbit stable at high warp]")
	var u := _load()
	var ves := Vessel.new(u, u.by_name["Veridia"])
	ves.set_circular_orbit(100_000.0)
	var alt0 := ves.altitude()
	ves.advance(30.0 * 86_400.0)  # 30 days
	_check(absf(ves.altitude() - alt0) < 1.0, "altitude unchanged after 30 days",
			"(delta %s m)" % _sci(absf(ves.altitude() - alt0)))
	_check(ves.parent.body_name == "Veridia", "still around Veridia")


func _test_node_execution() -> void:
	print("\n[maneuver node execution]")
	var u := _load()
	var ves := Vessel.new(u, u.by_name["Veridia"])
	ves.set_circular_orbit(100_000.0)
	var node := ManeuverNode.new(600.0)
	node.prograde = 100.0
	var info0: Dictionary = Kepler.orbit_info(ves.r, ves.v, ves.parent.mu)
	ves.advance(1200.0, [node])
	var info1: Dictionary = Kepler.orbit_info(ves.r, ves.v, ves.parent.mu)
	_check(node.executed, "node executed")
	_check(info1["ra"] > info0["ra"] + 100_000.0, "apoapsis raised by prograde burn",
			"(%.0f -> %.0f km)" % [info0["ra"] / 1000.0, info1["ra"] / 1000.0])
	_check(absf(info1["rp"] - info0["rp"]) < 5_000.0, "periapsis roughly unchanged")


## Full patched-conics trip through the hierarchy machinery, and the
## trajectory predictor must agree with the actual flight.
func _test_transfer_to_moon() -> void:
	print("\n[transfer to Cinder: prediction matches flight]")
	var u := _load()
	var veridia: CelestialBody = u.by_name["Veridia"]
	var cinder: CelestialBody = u.by_name["Cinder"]
	var ves := Vessel.new(u, veridia)

	# Hohmann-ish transfer from 700 km radius to the moon's orbit, phased so we
	# arrive when the moon does (moon starts at m0 = 110 deg).
	var rp := 700_000.0
	var a := (rp + cinder.orbit.a) / 2.0
	var transfer_time: float = PI * sqrt(a * a * a / veridia.mu)
	var arrival_angle := PI  # we launch from angle 0, arrive at 180 deg
	var moon_now := deg_to_rad(110.0)
	var moon_at_arrival := moon_now + cinder.orbit.mean_motion() * transfer_time
	# Rotate our departure point so that apoapsis lines up with the moon.
	var phase_err := fposmod(moon_at_arrival - arrival_angle, TAU)
	# Start position rotated by phase_err around +Y.
	var c := cos(phase_err)
	var s := sin(phase_err)
	var vp := sqrt(veridia.mu * (2.0 / rp - 1.0 / a))
	var r0 := DVec3.new(rp * c, 0.0, rp * s)
	var v0 := DVec3.new(-vp * s, 0.0, vp * c)
	ves.set_state(r0, v0)

	var predicted: Dictionary = Trajectory.predict(ves.parent, ves.r, ves.v, ves.t)
	var enters_moon := false
	for patch: Dictionary in predicted["patches"]:
		if patch["parent"] == cinder:
			enters_moon = true
	_check(enters_moon, "prediction shows Cinder encounter",
			"(%d patches)" % predicted["patches"].size())

	ves.advance(transfer_time * 1.05)
	_check(ves.parent == cinder, "vessel actually entered Cinder SOI",
			"(parent: %s, switches: %d)" % [ves.parent.body_name, ves.soi_switch_count])


## A trajectory that gets near the moon without entering its SOI must report
## a closest approach instead of an encounter.
func _test_closest_approach() -> void:
	print("\n[closest approach reported on a near-miss]")
	var u := _load()
	var veridia: CelestialBody = u.by_name["Veridia"]
	var cinder: CelestialBody = u.by_name["Cinder"]
	var ves := Vessel.new(u, veridia)

	# Apoapsis short of the moon's orbit by ~2x its SOI: near miss, no entry.
	var rp := 700_000.0
	var ra: float = cinder.orbit.a - cinder.soi * 2.0
	var a := (rp + ra) / 2.0
	var vp := sqrt(veridia.mu * (2.0 / rp - 1.0 / a))
	ves.set_state(DVec3.new(rp, 0.0, 0.0), DVec3.new(0.0, 0.0, vp))

	var predicted: Dictionary = Trajectory.predict(ves.parent, ves.r, ves.v, ves.t)
	_check(predicted["patches"].size() == 1, "no encounter patches",
			"(%d)" % predicted["patches"].size())
	var found := false
	for ap: Dictionary in predicted["approaches"]:
		if ap["body"] == cinder:
			found = true
			_check(ap["dist"] > cinder.soi and ap["dist"] < cinder.soi * 12.0,
					"approach distance plausible", "(%.0f km)" % (ap["dist"] / 1000.0))
	_check(found, "Cinder closest approach reported")
