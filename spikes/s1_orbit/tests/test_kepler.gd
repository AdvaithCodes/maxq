## Headless acceptance tests for Spike S1 (roadmap gate G0).
## Run:  godot --headless --path spikes/s1_orbit --script res://tests/test_kepler.gd
extends SceneTree

# Kerbin-like system.
const MU_PLANET := 3.5316e12
const R_PLANET := 600_000.0
const MU_MOON := 6.5138e10
const R_MOON := 200_000.0
const MOON_ORBIT_R := 12_000_000.0

var _failures := 0


func _initialize() -> void:
	print("=== Spike S1 acceptance tests ===")
	_test_energy_drift_1000_orbits()
	_test_elliptic_periodicity()
	_test_hyperbolic_energy()
	_test_back_and_forward()
	_test_soi_handoff_continuity()

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


## Criterion: specific-energy drift < 0.1% over 1000 orbits.
func _test_energy_drift_1000_orbits() -> void:
	print("\n[energy drift, circular 800 km orbit, 1000 periods]")
	var r0 := DVec3.new(800_000.0, 0.0, 0.0)
	var v0 := DVec3.new(0.0, 0.0, sqrt(MU_PLANET / 800_000.0))
	var e0 := Kepler.specific_energy(r0, v0, MU_PLANET)
	var period := Kepler.period(r0, v0, MU_PLANET)

	var max_drift := 0.0
	for i in range(1, 1001):
		# Sample at an irrational-ish fraction so we hit all orbit phases.
		var dt := period * (float(i) + 0.37)
		var out: Array = Kepler.propagate(r0, v0, MU_PLANET, dt)
		var e := Kepler.specific_energy(out[0], out[1], MU_PLANET)
		max_drift = maxf(max_drift, absf((e - e0) / e0))
	_check(max_drift < 0.001, "energy drift < 0.1%", "(max %s)" % _sci(max_drift))


## Propagating an elliptic orbit by exactly one period returns to the start.
func _test_elliptic_periodicity() -> void:
	print("\n[elliptic periodicity, 700 x 12000 km orbit]")
	var rp := 700_000.0
	var ra := MOON_ORBIT_R
	var a := (rp + ra) / 2.0
	var vp := sqrt(MU_PLANET * (2.0 / rp - 1.0 / a))
	var r0 := DVec3.new(rp, 0.0, 0.0)
	var v0 := DVec3.new(0.0, 0.0, vp)
	var period := Kepler.period(r0, v0, MU_PLANET)

	var out: Array = Kepler.propagate(r0, v0, MU_PLANET, period)
	var pos_err: float = out[0].sub(r0).length()
	var vel_err: float = out[1].sub(v0).length()
	_check(pos_err < 1.0, "position closes within 1 m", "(err %.6f m)" % pos_err)
	_check(vel_err < 0.001, "velocity closes within 1 mm/s", "(err %s m/s)" % _sci(vel_err))


## Hyperbolic propagation conserves (positive) energy.
func _test_hyperbolic_energy() -> void:
	print("\n[hyperbolic orbit energy conservation]")
	var r0 := DVec3.new(700_000.0, 0.0, 0.0)
	var v_esc := sqrt(2.0 * MU_PLANET / 700_000.0)
	var v0 := DVec3.new(0.0, 300.0, v_esc * 1.5)
	var e0 := Kepler.specific_energy(r0, v0, MU_PLANET)

	var ok := e0 > 0.0
	var max_err := 0.0
	for i in range(1, 21):
		var out: Array = Kepler.propagate(r0, v0, MU_PLANET, 10_000.0 * float(i))
		var e := Kepler.specific_energy(out[0], out[1], MU_PLANET)
		max_err = maxf(max_err, absf((e - e0) / e0))
	_check(ok and max_err < 1.0e-6, "hyperbolic energy conserved", "(max rel err %s)" % _sci(max_err))


## Propagating +dt then -dt returns to the initial state (reversibility).
func _test_back_and_forward() -> void:
	print("\n[reversibility: +dt then -dt]")
	var r0 := DVec3.new(650_000.0, 50_000.0, 0.0)
	var v0 := DVec3.new(-200.0, 0.0, 2500.0)
	var fwd: Array = Kepler.propagate(r0, v0, MU_PLANET, 12_345.0)
	var back: Array = Kepler.propagate(fwd[0], fwd[1], MU_PLANET, -12_345.0)
	var pos_err: float = back[0].sub(r0).length()
	_check(pos_err < 0.01, "round trip within 1 cm", "(err %s m)" % _sci(pos_err))


## Criterion: SOI handoff has no position discontinuity (> 1 m jump between
## consecutive samples beyond what velocity explains), and the vessel actually
## enters and exits the moon's SOI on a transfer orbit.
func _test_soi_handoff_continuity() -> void:
	print("\n[SOI handoff continuity, transfer to moon]")
	var planet := CelestialBody.new("Planet", MU_PLANET, R_PLANET)
	var moon := CelestialBody.new("Moon", MU_MOON, R_MOON)
	moon.set_circular_orbit(MU_PLANET, MOON_ORBIT_R, 1.932)
	print("  moon SOI radius: %.0f km" % (moon.soi / 1000.0))

	var sim := OrbitSim.new(planet, moon)
	var rp := 700_000.0
	var a := (rp + MOON_ORBIT_R) / 2.0
	var vp := sqrt(MU_PLANET * (2.0 / rp - 1.0 / a))
	sim.set_state(DVec3.new(rp, 0.0, 0.0), DVec3.new(0.0, 0.0, vp))

	var dt := 10.0
	var transfer_period := Kepler.period(sim.r, sim.v, MU_PLANET)
	var min_moon_dist := INF

	var steps := int(transfer_period * 1.5 / dt)
	for i in steps:
		sim.advance(sim.t + dt)
		if sim.parent_is_moon:
			min_moon_dist = minf(min_moon_dist, sim.r.length())

	_check(sim.soi_switch_count >= 2, "entered and exited moon SOI",
			"(%d switches, closest approach %.0f km)" %
			[sim.soi_switch_count, min_moon_dist / 1000.0])
	_check(sim.max_switch_jump < 1.0, "handoff discontinuity < 1 m",
			"(max %s m)" % _sci(sim.max_switch_jump))
