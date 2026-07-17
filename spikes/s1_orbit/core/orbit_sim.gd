## On-rails vessel simulation with patched-conics SOI transitions between a
## planet (inertial root at origin) and its moon (circular on-rails orbit).
##
## The vessel's state is stored as an epoch (r, v, t) relative to its current
## parent body and propagated analytically — no error accumulation, works at
## any time warp.
class_name OrbitSim
extends RefCounted

## Hysteresis so a vessel exactly on the boundary doesn't flip-flop each step.
const SOI_ENTER_FACTOR := 0.999
const SOI_EXIT_FACTOR := 1.001
## Max propagation step for SOI-crossing detection at high warp (s).
const MAX_STEP := 600.0

var planet: CelestialBody
var moon: CelestialBody

var t: float = 0.0
var parent_is_moon := false
var soi_switch_count := 0
## Largest world-position discontinuity introduced by an SOI re-parenting (m).
var max_switch_jump := 0.0

# Epoch state (relative to current parent).
var _epoch_t: float = 0.0
var _epoch_r: DVec3
var _epoch_v: DVec3

# Current state (relative to current parent), cached by advance().
var r: DVec3
var v: DVec3


func _init(p_planet: CelestialBody, p_moon: CelestialBody) -> void:
	planet = p_planet
	moon = p_moon


## Set vessel state relative to the current parent at the current time.
func set_state(p_r: DVec3, p_v: DVec3) -> void:
	_epoch_t = t
	_epoch_r = p_r.copy()
	_epoch_v = p_v.copy()
	r = p_r.copy()
	v = p_v.copy()


func _parent_mu() -> float:
	return moon.mu if parent_is_moon else planet.mu


## Advance simulation time to to_t (must be >= t), substepping so SOI
## crossings are not skipped at high warp.
func advance(to_t: float) -> void:
	while t < to_t:
		var step: float = minf(MAX_STEP, to_t - t)
		t += step
		var out: Array = Kepler.propagate(_epoch_r, _epoch_v, _parent_mu(), t - _epoch_t)
		r = out[0]
		v = out[1]
		_check_soi_transition()


func _check_soi_transition() -> void:
	if not parent_is_moon:
		# Planet frame: entering the moon's SOI?
		var rel_r: DVec3 = r.sub(moon.pos_at(t))
		if rel_r.length() < moon.soi * SOI_ENTER_FACTOR:
			var wp_before: DVec3 = world_pos()
			var rel_v: DVec3 = v.sub(moon.vel_at(t))
			parent_is_moon = true
			soi_switch_count += 1
			set_state(rel_r, rel_v)
			max_switch_jump = maxf(max_switch_jump, world_pos().sub(wp_before).length())
	else:
		# Moon frame: leaving the moon's SOI?
		if r.length() > moon.soi * SOI_EXIT_FACTOR:
			var wp_before: DVec3 = world_pos()
			var abs_r: DVec3 = r.add(moon.pos_at(t))
			var abs_v: DVec3 = v.add(moon.vel_at(t))
			parent_is_moon = false
			soi_switch_count += 1
			set_state(abs_r, abs_v)
			max_switch_jump = maxf(max_switch_jump, world_pos().sub(wp_before).length())


## Vessel position in the planet-centered inertial frame.
func world_pos() -> DVec3:
	return r.add(moon.pos_at(t)) if parent_is_moon else r.copy()


## Vessel velocity in the planet-centered inertial frame.
func world_vel() -> DVec3:
	return v.add(moon.vel_at(t)) if parent_is_moon else v.copy()


func parent_name() -> String:
	return moon.body_name if parent_is_moon else planet.body_name


## Altitude above the current parent's surface (m).
func altitude() -> float:
	var parent_radius: float = moon.radius if parent_is_moon else planet.radius
	return r.length() - parent_radius
