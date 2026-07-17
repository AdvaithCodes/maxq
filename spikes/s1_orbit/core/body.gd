## Celestial body on a circular on-rails orbit around its parent (spike-grade:
## the real game will give bodies full Kepler elements).
class_name CelestialBody
extends RefCounted

var body_name: String
var mu: float           # gravitational parameter GM, m^3/s^2
var radius: float       # m
var soi: float          # sphere-of-influence radius, m (INF for the root body)
var orbit_radius: float # m, around parent (0 for the root body)
var phase0: float       # rad, orbital phase at t=0
var mean_motion: float  # rad/s


func _init(p_name: String, p_mu: float, p_radius: float) -> void:
	body_name = p_name
	mu = p_mu
	radius = p_radius
	soi = INF
	orbit_radius = 0.0
	phase0 = 0.0
	mean_motion = 0.0


## Configure a circular orbit around a parent body.
func set_circular_orbit(parent_mu: float, p_orbit_radius: float, p_phase0: float) -> void:
	orbit_radius = p_orbit_radius
	phase0 = p_phase0
	mean_motion = sqrt(parent_mu / (orbit_radius * orbit_radius * orbit_radius))
	# SOI radius: r_soi = a * (m / M)^(2/5)
	soi = orbit_radius * pow(mu / parent_mu, 0.4)


## Position relative to parent at time t (orbit in the XZ plane).
func pos_at(t: float) -> DVec3:
	var ang := phase0 + mean_motion * t
	return DVec3.new(orbit_radius * cos(ang), 0.0, orbit_radius * sin(ang))


## Velocity relative to parent at time t.
func vel_at(t: float) -> DVec3:
	var ang := phase0 + mean_motion * t
	var speed := mean_motion * orbit_radius
	return DVec3.new(-speed * sin(ang), 0.0, speed * cos(ang))
