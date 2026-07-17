## Free-fly camera with a double-precision world position.
## The camera NODE never moves from the render-space origin — `dpos` (doubles,
## planet-relative) is the true position, and the world is drawn relative to it.
class_name FlyCam
extends Camera3D

var dpos: DVec3 = DVec3.new()
var speed := 20_000.0  # m/s
var auto_speed := true

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	near = 2.0
	far = 3.0e6
	position = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed *= 1.3
			auto_speed = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed /= 1.3
			auto_speed = false
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.55, 1.55)
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()
			KEY_F:
				auto_speed = not auto_speed


func fly(delta: float, altitude: float) -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
	if auto_speed:
		# Faster when high, slower near the ground.
		speed = clampf(absf(altitude) * 0.75, 10.0, 60_000.0)

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= basis.z
	if Input.is_key_pressed(KEY_S):
		dir += basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= basis.x
	if Input.is_key_pressed(KEY_D):
		dir += basis.x
	if Input.is_key_pressed(KEY_Q):
		dir -= basis.y
	if Input.is_key_pressed(KEY_E):
		dir += basis.y
	if dir != Vector3.ZERO:
		dir = dir.normalized() * speed * delta
		dpos = dpos.add(DVec3.new(dir.x, dir.y, dir.z))
