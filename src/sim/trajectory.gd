## Patched-conics trajectory prediction for map view: propagates a copy of the
## vessel state forward (including planned maneuver nodes), splitting into a
## new patch at every SOI transition.
##
## Each patch's points are PARENT-RELATIVE; the renderer translates them to the
## parent's CURRENT world position (KSP map-view convention: you see the shape
## of your orbit around the body, not a world-space spaghetti line).
class_name Trajectory
extends RefCounted

const MAX_PATCHES := 4
const SAMPLES_PER_PATCH := 220
const HYPERBOLIC_HORIZON := 4.0e6  # s of sampling for escape trajectories


## Returns Array of patches:
##   { parent: CelestialBody, pts: Array[DVec3], markers: Array[DVec3],
##     t_start: float, t_end: float }
## markers = node positions that occur within the patch (parent-relative).
static func predict(parent: CelestialBody, r0: DVec3, v0: DVec3, t0: float,
		nodes: Array = []) -> Array:
	var patches: Array = []
	var p := parent
	var er := r0.copy()
	var ev := v0.copy()
	var et := t0
	var t := t0

	var pending: Array = []
	for n: ManeuverNode in nodes:
		if not n.executed and n.t > t0:
			pending.append(n)
	pending.sort_custom(func(x: ManeuverNode, y: ManeuverNode) -> bool: return x.t < y.t)

	while patches.size() < MAX_PATCHES:
		var span := _patch_span(er, ev, p.mu)
		# Extend the first patch to reach any planned node.
		if not pending.is_empty():
			span = maxf(span, pending[0].t - t + 60.0)
		var t_end := t + span
		var dt := span / float(SAMPLES_PER_PATCH)
		var patch := {
			"parent": p, "pts": [] as Array, "markers": [] as Array,
			"t_start": t, "t_end": t_end,
		}
		patch["pts"].append(er.copy())
		var switched := false

		while t < t_end:
			var step: float = minf(dt, t_end - t)
			if not pending.is_empty() and pending[0].t > t and pending[0].t <= t + step:
				step = pending[0].t - t
			t += step
			var out: Array = Kepler.propagate(er, ev, p.mu, t - et)
			var cr: DVec3 = out[0]
			var cv: DVec3 = out[1]

			if not pending.is_empty() and absf(t - pending[0].t) < 1.0e-6:
				var n: ManeuverNode = pending.pop_front()
				cv = cv.add(n.dv_world(cr, cv))
				patch["markers"].append(cr.copy())
				er = cr
				ev = cv
				et = t
				# Orbit changed: recompute this patch's horizon.
				t_end = t + _patch_span(er, ev, p.mu)
				patch["t_end"] = t_end
				dt = (t_end - t) / float(SAMPLES_PER_PATCH)

			patch["pts"].append(cr)

			var chk := Vessel.soi_check(p, cr, cv, t)
			if chk[3]:
				p = chk[0]
				er = chk[1]
				ev = chk[2]
				et = t
				switched = true
				break

		patch["t_end"] = t
		patches.append(patch)
		if not switched:
			break
	return patches


## How long to sample a conic in this patch: one period for closed orbits,
## a fixed horizon for escape trajectories (SOI exit will cut it short).
static func _patch_span(r: DVec3, v: DVec3, mu: float) -> float:
	var period := Kepler.period(r, v, mu)
	return period if period != INF else HYPERBOLIC_HORIZON
