## Classical Keplerian orbital elements for on-rails celestial bodies
## (elliptic only — bodies don't fly hyperbolic orbits). All math in doubles.
## Convention: Y-up. The reference plane is XZ; inclination tilts about X.
class_name OrbitElements
extends RefCounted

var a: float      # semi-major axis, m
var e: float      # eccentricity [0, 1)
var inc: float    # inclination, rad
var raan: float   # longitude of ascending node, rad
var argp: float   # argument of periapsis, rad
var m0: float     # mean anomaly at t = 0, rad
var mu: float     # gravitational parameter of the PARENT body


static func from_dict(d: Dictionary, parent_mu: float) -> OrbitElements:
	var o := OrbitElements.new()
	o.a = d.get("a", 0.0)
	o.e = d.get("e", 0.0)
	o.inc = deg_to_rad(d.get("inc_deg", 0.0))
	o.raan = deg_to_rad(d.get("raan_deg", 0.0))
	o.argp = deg_to_rad(d.get("argp_deg", 0.0))
	o.m0 = deg_to_rad(d.get("m0_deg", 0.0))
	o.mu = parent_mu
	return o


func mean_motion() -> float:
	return sqrt(mu / (a * a * a))


func period() -> float:
	return TAU / mean_motion()


## Solve Kepler's equation M = E - e*sin(E) for eccentric anomaly.
func eccentric_anomaly(m: float) -> float:
	m = fposmod(m, TAU)
	var ecc_e := m if e < 0.8 else PI
	for _i in 50:
		var f := ecc_e - e * sin(ecc_e) - m
		var df := 1.0 - e * cos(ecc_e)
		var step := f / df
		ecc_e -= step
		if absf(step) < 1.0e-13:
			break
	return ecc_e


## Rotate a perifocal-frame vector (p toward periapsis, q 90 deg ahead in the
## orbital plane) into the parent frame.
func _to_parent_frame(px: float, pz: float) -> DVec3:
	# Ry(argp)
	var c := cos(argp)
	var s := sin(argp)
	var x1 := px * c + pz * s
	var z1 := -px * s + pz * c
	# Rx(inc)
	var ci := cos(inc)
	var si := sin(inc)
	var y2 := -z1 * si
	var z2 := z1 * ci
	# Ry(raan)
	var cr := cos(raan)
	var sr := sin(raan)
	return DVec3.new(x1 * cr + z2 * sr, y2, -x1 * sr + z2 * cr)


func pos_at(t: float) -> DVec3:
	var ecc_e := eccentric_anomaly(m0 + mean_motion() * t)
	var px := a * (cos(ecc_e) - e)
	var pz := a * sqrt(1.0 - e * e) * sin(ecc_e)
	return _to_parent_frame(px, pz)


func vel_at(t: float) -> DVec3:
	var ecc_e := eccentric_anomaly(m0 + mean_motion() * t)
	var edot := mean_motion() / (1.0 - e * cos(ecc_e))
	var vx := -a * sin(ecc_e) * edot
	var vz := a * sqrt(1.0 - e * e) * cos(ecc_e) * edot
	return _to_parent_frame(vx, vz)


## Sample one full orbit as parent-relative points (for orbit line rendering).
func sample_points(count: int) -> Array:
	var pts: Array = []
	for k in count + 1:
		var ecc_e := TAU * float(k) / float(count)
		var px := a * (cos(ecc_e) - e)
		var pz := a * sqrt(1.0 - e * e) * sin(ecc_e)
		pts.append(_to_parent_frame(px, pz))
	return pts
