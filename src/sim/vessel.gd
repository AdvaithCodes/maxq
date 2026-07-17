## On-rails vessel: epoch state relative to a parent body, propagated
## analytically, with patched-conics SOI transitions across the whole body
## hierarchy and impulsive maneuver-node execution.
class_name Vessel
extends RefCounted

const SOI_ENTER_FACTOR := 0.999
const SOI_EXIT_FACTOR := 1.001
const MAX_STEP := 600.0  # s, so SOI crossings aren't skipped at high warp

var universe: Universe
var parent: CelestialBody
var t := 0.0
var soi_switch_count := 0

var _epoch_t := 0.0
var _epoch_r: DVec3
var _epoch_v: DVec3

# Current parent-relative state (cached by advance/set_state).
var r: DVec3
var v: DVec3


func _init(p_universe: Universe, p_parent: CelestialBody) -> void:
	universe = p_universe
	parent = p_parent


func set_state(p_r: DVec3, p_v: DVec3) -> void:
	_epoch_t = t
	_epoch_r = p_r.copy()
	_epoch_v = p_v.copy()
	r = p_r.copy()
	v = p_v.copy()


## Place the vessel in a circular equatorial orbit at the given altitude.
func set_circular_orbit(altitude: float) -> void:
	var rr := parent.radius + altitude
	set_state(DVec3.new(rr, 0.0, 0.0), DVec3.new(0.0, 0.0, sqrt(parent.mu / rr)))


## One patched-conics transition check. Static so the trajectory predictor
## shares the exact same rules. Returns [parent, r, v, changed: bool].
static func soi_check(p: CelestialBody, pr: DVec3, pv: DVec3, at_t: float) -> Array:
	# Descend into a child SOI?
	for child: CelestialBody in p.children:
		var rel: DVec3 = pr.sub(child.local_pos_at(at_t))
		if rel.length() < child.soi * SOI_ENTER_FACTOR:
			return [child, rel, pv.sub(child.local_vel_at(at_t)), true]
	# Ascend to the parent's parent?
	if p.parent != null and pr.length() > p.soi * SOI_EXIT_FACTOR:
		return [p.parent, pr.add(p.local_pos_at(at_t)), pv.add(p.local_vel_at(at_t)), true]
	return [p, pr, pv, false]


## Advance to universal time to_t, executing due maneuver nodes on the way.
func advance(to_t: float, nodes: Array = []) -> void:
	while t < to_t:
		# Next unexecuted node inside this step, if any.
		var step: float = minf(MAX_STEP, to_t - t)
		var node: ManeuverNode = null
		for n: ManeuverNode in nodes:
			if not n.executed and n.t > t and n.t <= t + step:
				if node == null or n.t < node.t:
					node = n
		if node != null:
			step = node.t - t

		t += step
		var out: Array = Kepler.propagate(_epoch_r, _epoch_v, parent.mu, t - _epoch_t)
		r = out[0]
		v = out[1]

		if node != null:
			node.executed = true
			set_state(r, v.add(node.dv_world(r, v)))

		var chk := soi_check(parent, r, v, t)
		if chk[3]:
			parent = chk[0]
			soi_switch_count += 1
			set_state(chk[1], chk[2])


func world_pos() -> DVec3:
	return parent.world_pos_at(t).add(r)


func altitude() -> float:
	return r.length() - parent.radius
