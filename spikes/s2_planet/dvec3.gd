## Double-precision 3D vector.
## GDScript scalar `float` is 64-bit; engine Vector3 components are 32-bit in
## standard builds, so orbital state must never touch Vector3 except for display.
class_name DVec3
extends RefCounted

var x: float
var y: float
var z: float


func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0) -> void:
	x = px
	y = py
	z = pz


func copy() -> DVec3:
	return DVec3.new(x, y, z)


func add(o: DVec3) -> DVec3:
	return DVec3.new(x + o.x, y + o.y, z + o.z)


func sub(o: DVec3) -> DVec3:
	return DVec3.new(x - o.x, y - o.y, z - o.z)


func mul(s: float) -> DVec3:
	return DVec3.new(x * s, y * s, z * s)


func dot(o: DVec3) -> float:
	return x * o.x + y * o.y + z * o.z


func cross(o: DVec3) -> DVec3:
	return DVec3.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)


func length_sq() -> float:
	return x * x + y * y + z * z


func length() -> float:
	return sqrt(x * x + y * y + z * z)


func normalized() -> DVec3:
	var l := length()
	return DVec3.new(x / l, y / l, z / l) if l > 0.0 else DVec3.new()


## Lossy: for rendering/display only.
func to_v3() -> Vector3:
	return Vector3(x, y, z)
