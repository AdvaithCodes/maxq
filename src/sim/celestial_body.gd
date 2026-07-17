## A celestial body in the on-rails hierarchy. The root body (star) is the
## inertial origin of the universe; every other body flies Kepler elements
## around its parent.
class_name CelestialBody
extends RefCounted

var body_name: String
var mu: float          # GM, m^3/s^2
var radius: float      # m
var soi: float         # sphere of influence radius, m (INF for the root)
var color: Color
var parent: CelestialBody = null
var children: Array[CelestialBody] = []
var orbit: OrbitElements = null   # null for the root body


## Position relative to parent at time t.
func local_pos_at(t: float) -> DVec3:
	return orbit.pos_at(t) if orbit else DVec3.new()


## Velocity relative to parent at time t.
func local_vel_at(t: float) -> DVec3:
	return orbit.vel_at(t) if orbit else DVec3.new()


## Absolute (root-frame) position at time t.
func world_pos_at(t: float) -> DVec3:
	var p := local_pos_at(t)
	return parent.world_pos_at(t).add(p) if parent else p


## Absolute (root-frame) velocity at time t.
func world_vel_at(t: float) -> DVec3:
	var v := local_vel_at(t)
	return parent.world_vel_at(t).add(v) if parent else v
