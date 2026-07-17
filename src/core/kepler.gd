## Universal-variable Kepler propagator (Curtis, "Orbital Mechanics for
## Engineering Students", Algorithm 3.4). Handles elliptic, parabolic and
## hyperbolic orbits with one formulation. All math in 64-bit scalars.
##
## Key property: propagation is analytic from an epoch state, so there is no
## error accumulation over time — propagating 1000 orbits is as accurate as
## propagating one frame.
class_name Kepler
extends RefCounted

const NEWTON_TOL := 1.0e-10
const MAX_ITER := 200


static func _cosh(v: float) -> float:
	return (exp(v) + exp(-v)) * 0.5


static func _sinh(v: float) -> float:
	return (exp(v) - exp(-v)) * 0.5


## Stumpff function C(z).
static func stumpff_c(z: float) -> float:
	if z > 1.0e-8:
		return (1.0 - cos(sqrt(z))) / z
	elif z < -1.0e-8:
		return (_cosh(sqrt(-z)) - 1.0) / (-z)
	return 0.5 - z / 24.0  # series expansion near zero


## Stumpff function S(z).
static func stumpff_s(z: float) -> float:
	if z > 1.0e-8:
		var sz := sqrt(z)
		return (sz - sin(sz)) / (z * sz)
	elif z < -1.0e-8:
		var sz := sqrt(-z)
		return (_sinh(sz) - sz) / (-z * sz)
	return 1.0 / 6.0 - z / 120.0


## Propagate state (r0, v0) around a body of gravitational parameter mu by dt
## seconds (dt may be negative). Returns [r: DVec3, v: DVec3].
static func propagate(r0: DVec3, v0: DVec3, mu: float, dt: float) -> Array:
	if absf(dt) < 1.0e-12:
		return [r0.copy(), v0.copy()]

	var r0m := r0.length()
	var v0m2 := v0.length_sq()
	var vr0 := r0.dot(v0) / r0m
	var alpha := 2.0 / r0m - v0m2 / mu  # 1/a; >0 elliptic, <0 hyperbolic
	var smu := sqrt(mu)

	var chi := _solve_universal(r0m, vr0, alpha, smu, dt)

	# Lagrange f and g coefficients.
	var zf := alpha * chi * chi
	var cf := stumpff_c(zf)
	var sf := stumpff_s(zf)
	var lf := 1.0 - chi * chi / r0m * cf
	var lg := dt - chi * chi * chi * sf / smu

	var r := r0.mul(lf).add(v0.mul(lg))
	var rm := r.length()

	var lfdot := smu / (rm * r0m) * (alpha * chi * chi * chi * sf - chi)
	var lgdot := 1.0 - chi * chi / rm * cf
	var v := r0.mul(lfdot).add(v0.mul(lgdot))
	return [r, v]


## Universal Kepler equation F(chi) (zero at the solution). Monotonically
## increasing in chi, since dF/dchi is the orbital radius (always > 0).
static func _f_univ(chi: float, r0m: float, vr0: float, alpha: float, smu: float, dt: float) -> float:
	var z := alpha * chi * chi
	var c := stumpff_c(z)
	var s := stumpff_s(z)
	var f := r0m * vr0 / smu * chi * chi * c \
			+ (1.0 - alpha * r0m) * chi * chi * chi * s \
			+ r0m * chi - smu * dt
	if not is_finite(f):
		# Stumpff exp() overflow far outside the root (hyperbolic, large |chi|).
		# F is monotonic and diverges with chi, so the sign of chi is the sign of F.
		return INF * signf(chi)
	return f


static func _df_univ(chi: float, r0m: float, vr0: float, alpha: float, smu: float) -> float:
	var z := alpha * chi * chi
	var c := stumpff_c(z)
	var s := stumpff_s(z)
	return r0m * vr0 / smu * chi * (1.0 - z * s) \
			+ (1.0 - alpha * r0m) * chi * chi * c + r0m


## Solve the universal Kepler equation for chi with a bracketed Newton method.
## Since F is monotonic, bisection fallback makes this unconditionally
## convergent — plain Newton diverges on hyperbolic orbits (e.g. moon flybys).
static func _solve_universal(r0m: float, vr0: float, alpha: float, smu: float, dt: float) -> float:
	var guess := smu * absf(alpha) * dt if absf(alpha) > 1.0e-12 else smu * dt / r0m

	# Bracket the root: F(0) = -smu*dt, so chi has the same sign as dt.
	var lo := 0.0
	var hi := 0.0
	if dt > 0.0:
		hi = maxf(maxf(guess, smu * dt / r0m), 1.0e-6)
		while _f_univ(hi, r0m, vr0, alpha, smu, dt) < 0.0:
			hi *= 2.0
	else:
		lo = minf(minf(guess, smu * dt / r0m), -1.0e-6)
		while _f_univ(lo, r0m, vr0, alpha, smu, dt) > 0.0:
			lo *= 2.0

	# Safeguarded Newton (Numerical Recipes "rtsafe"). The root stays bracketed
	# in [lo, hi]; Newton is only accepted when it shrinks faster than
	# bisection, otherwise we bisect. This matters for hyperbolic orbits where
	# F grows exponentially and raw Newton "creeps" in fixed-size steps.
	var chi := (lo + hi) * 0.5
	var dx_old := hi - lo
	for _i in MAX_ITER:
		if hi - lo < NEWTON_TOL * maxf(1.0, absf(chi)):
			break
		var fv := _f_univ(chi, r0m, vr0, alpha, smu, dt)
		if fv == 0.0:
			break
		if fv > 0.0:
			hi = chi
		else:
			lo = chi
		var dfv := _df_univ(chi, r0m, vr0, alpha, smu)
		var newton := chi - fv / dfv
		if is_finite(newton) and newton > lo and newton < hi \
				and absf(2.0 * fv) <= absf(dx_old * dfv):
			dx_old = absf(newton - chi)
			chi = newton
		else:
			dx_old = (hi - lo) * 0.5
			chi = (lo + hi) * 0.5
	return chi


## Specific orbital energy (J/kg). Conserved on a Kepler orbit.
static func specific_energy(r: DVec3, v: DVec3, mu: float) -> float:
	return v.length_sq() * 0.5 - mu / r.length()


## Orbital period in seconds (INF for non-elliptic orbits).
static func period(r: DVec3, v: DVec3, mu: float) -> float:
	var eps := specific_energy(r, v, mu)
	if eps >= 0.0:
		return INF
	var a := -mu / (2.0 * eps)
	return TAU * sqrt(a * a * a / mu)


## Scalar orbit summary from a state vector, for HUD display.
## Returns {a, e, rp, ra, period} (ra/period are INF for open orbits).
static func orbit_info(r: DVec3, v: DVec3, mu: float) -> Dictionary:
	var rm := r.length()
	var v2 := v.length_sq()
	# Eccentricity vector: e = ((v^2 - mu/r) r - (r.v) v) / mu
	var evec := r.mul(v2 - mu / rm).sub(v.mul(r.dot(v))).mul(1.0 / mu)
	var e := evec.length()
	var eps := v2 * 0.5 - mu / rm
	var a := -mu / (2.0 * eps) if absf(eps) > 1.0e-12 else INF
	var rp := a * (1.0 - e) if a != INF else rm
	var ra := a * (1.0 + e) if eps < 0.0 else INF
	var per := TAU * sqrt(a * a * a / mu) if eps < 0.0 else INF
	return {"a": a, "e": e, "rp": rp, "ra": ra, "period": per}
