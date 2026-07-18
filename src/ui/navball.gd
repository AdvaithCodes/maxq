## The navball: a 3D attitude sphere rendered in its own SubViewport.
## Shows the local-horizon sphere (sky/ground hemispheres + lat/lon grid) as
## seen from behind the ship's nose, with prograde/retrograde markers.
##
## Math: ship basis B (nose = +Y), horizon basis H (columns east, up, north).
## View mapping A sends world dirs to navball-view space so that the nose is
## at the ball center facing the camera: A = Basis(B.x, -B.z, B.y)^T.
## The ball (textured in horizon coordinates) gets basis A * H; a marker for
## world direction w sits at A * w on the sphere.
class_name Navball
extends SubViewportContainer

const BALL_R := 0.95

var _vp: SubViewport
var _ball: MeshInstance3D
var _prograde: MeshInstance3D
var _retrograde: MeshInstance3D

const BALL_SHADER := "
shader_type spatial;
render_mode unshaded;
varying vec3 vtx;
void vertex() { vtx = VERTEX; }
void fragment() {
	vec3 d = normalize(vtx);
	float lat = degrees(asin(clamp(d.y, -1.0, 1.0)));
	float lon = degrees(atan(d.x, d.z));
	vec3 sky = vec3(0.16, 0.38, 0.72);
	vec3 gnd = vec3(0.42, 0.26, 0.11);
	vec3 col = d.y >= 0.0 ? sky : gnd;
	float glat = abs(fract(lat / 30.0 + 0.5) - 0.5) * 30.0;
	float glon = abs(fract(lon / 30.0 + 0.5) - 0.5) * 30.0;
	float line = min(glat, glon * max(cos(radians(lat)), 0.15));
	col = mix(vec3(0.85), col, smoothstep(0.5, 1.1, line));
	col = mix(vec3(1.0), col, smoothstep(0.0, 1.0, abs(lat)));
	ALBEDO = col;
}
"


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(220, 220)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.size = Vector2i(220, 220)
	add_child(_vp)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.1
	cam.position = Vector3(0, 0, 2.0)
	_vp.add_child(cam)

	var sphere := SphereMesh.new()
	sphere.radius = BALL_R
	sphere.height = BALL_R * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_ball = MeshInstance3D.new()
	_ball.mesh = sphere
	var shader := Shader.new()
	shader.code = BALL_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_ball.material_override = mat
	_vp.add_child(_ball)

	_prograde = _marker(Color(1.0, 0.85, 0.2))
	_retrograde = _marker(Color(0.95, 0.35, 0.25))

	# Fixed center reticle (the ship's nose).
	var ret := _marker(Color(0.2, 1.0, 0.4))
	ret.position = Vector3(0, 0, BALL_R + 0.05)
	ret.scale = Vector3.ONE * 0.6


func _marker(color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material_override = mat
	_vp.add_child(m)
	return m


## ship: global basis of the controlled assembly (nose = +Y).
## horizon: Basis with columns (east, up, north).
## vel_world: ship velocity in the planet frame (for prograde markers).
func update_navball(ship: Basis, horizon: Basis, vel_world: Vector3) -> void:
	var a := Basis(ship.x, -ship.z, ship.y).transposed()
	_ball.transform.basis = a * horizon
	if vel_world.length() > 0.5:
		var wp := vel_world.normalized()
		_place(_prograde, a * wp)
		_place(_retrograde, a * -wp)
	else:
		_prograde.visible = false
		_retrograde.visible = false


func _place(m: MeshInstance3D, d: Vector3) -> void:
	m.visible = d.z > 0.05
	m.position = d * BALL_R
