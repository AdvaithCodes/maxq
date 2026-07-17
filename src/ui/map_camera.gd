## Map-view orbit camera: rotates around the render-space origin (the focus
## object is always drawn AT the origin — focus-relative rendering).
## Drag with left/right mouse to rotate, scroll to zoom.
class_name MapCamera
extends Camera3D

var yaw := 0.6
var pitch := -0.9
var dist := 0.22  # scene units (1 unit = 10,000 km); frames the starting orbit

var _dragging := false


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					dist = maxf(dist * 0.85, 0.002)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					dist = minf(dist * 1.18, 8000.0)
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.006, -1.55, 1.55)


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	position = basis * Vector3(0, 0, dist)
	transform.basis = basis
	near = maxf(dist * 0.01, 1.0e-4)
	far = maxf(dist * 400.0, 10_000.0)
