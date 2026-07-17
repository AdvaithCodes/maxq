## A planned impulsive burn at universal time t, expressed in the local
## prograde/normal/radial frame at execution.
class_name ManeuverNode
extends RefCounted

var t: float
var prograde: float = 0.0
var normal: float = 0.0
var radial: float = 0.0
var executed := false


func _init(p_t: float) -> void:
	t = p_t


func dv() -> float:
	return sqrt(prograde * prograde + normal * normal + radial * radial)


## World-frame delta-v for a vessel state (r, v) at execution time.
func dv_world(r: DVec3, v: DVec3) -> DVec3:
	var pro := v.normalized()
	var nrm := r.cross(v).normalized()
	var rad := pro.cross(nrm)
	return pro.mul(prograde).add(nrm.mul(normal)).add(rad.mul(radial))
