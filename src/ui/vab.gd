## Vehicle Assembly Building. v1 interaction: click parts to stack them top-
## down (first part is the root/pod), radial parts attach to the last stack
## part. Live delta-v / TWR readout, save/load to user://crafts/, Launch.
extends Node3D

const VERIDIA_G := 3.5316e12 / (600_000.0 * 600_000.0)

var craft: Craft
var _preview: Node3D
var _stats: Label
var _name_edit: LineEdit
var _status: Label

var _cam: Camera3D
var _cam_yaw := 0.6
var _cam_pitch := -0.1
var _cam_dist := 14.0
var _dragging := false


func _ready() -> void:
	craft = GameState.current_craft if GameState.current_craft else Craft.new()

	_preview = Node3D.new()
	add_child(_preview)
	_cam = Camera3D.new()
	add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment = e
	add_child(env)

	_build_ui()
	_rebuild_preview()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Left: part catalog.
	var left := PanelContainer.new()
	left.position = Vector2(10, 10)
	var lbox := VBoxContainer.new()
	left.add_child(lbox)
	var title := Label.new()
	title.text = "PARTS"
	title.add_theme_font_size_override("font_size", 20)
	lbox.add_child(title)
	var ids := GameState.catalog.keys()
	ids.sort()
	for id: String in ids:
		var def: PartDef = GameState.catalog[id]
		var btn := Button.new()
		btn.text = def.title
		btn.add_theme_font_size_override("font_size", 16)
		btn.tooltip_text = _part_tooltip(def)
		btn.pressed.connect(_on_add_part.bind(def))
		lbox.add_child(btn)
	var sep := HSeparator.new()
	lbox.add_child(sep)
	var undo := Button.new()
	undo.text = "Remove last part"
	undo.add_theme_font_size_override("font_size", 16)
	undo.pressed.connect(_on_undo)
	lbox.add_child(undo)
	var clear := Button.new()
	clear.text = "Clear craft"
	clear.add_theme_font_size_override("font_size", 16)
	clear.pressed.connect(_on_clear)
	lbox.add_child(clear)
	canvas.add_child(left)

	# Right: stats + actions.
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-330, 10)
	var rbox := VBoxContainer.new()
	rbox.custom_minimum_size = Vector2(320, 0)
	right.add_child(rbox)
	_name_edit = LineEdit.new()
	_name_edit.text = craft.craft_name
	_name_edit.add_theme_font_size_override("font_size", 17)
	rbox.add_child(_name_edit)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	rbox.add_child(_stats)
	var save := Button.new()
	save.text = "Save craft"
	save.add_theme_font_size_override("font_size", 16)
	save.pressed.connect(_on_save)
	rbox.add_child(save)
	var load_btn := Button.new()
	load_btn.text = "Load craft (by name)"
	load_btn.add_theme_font_size_override("font_size", 16)
	load_btn.pressed.connect(_on_load)
	rbox.add_child(load_btn)
	var test_btn := Button.new()
	test_btn.text = "Load default test rocket"
	test_btn.add_theme_font_size_override("font_size", 16)
	test_btn.pressed.connect(_on_default)
	rbox.add_child(test_btn)
	var launch := Button.new()
	launch.text = "LAUNCH"
	launch.add_theme_font_size_override("font_size", 24)
	launch.pressed.connect(_on_launch)
	rbox.add_child(launch)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rbox.add_child(_status)
	canvas.add_child(right)


func _part_tooltip(def: PartDef) -> String:
	var s := "%s\nmass %.0f kg" % [def.title, def.dry_mass]
	if def.fuel_capacity > 0.0:
		s += "  +%.0f kg fuel" % def.fuel_capacity
	if def.is_engine():
		s += "\nthrust %.0f kN  isp %.0f s" % [def.engine["thrust"] / 1000.0, def.engine["isp"]]
	return s


func _last_stack_index() -> int:
	for i in range(craft.parts.size() - 1, -1, -1):
		if not (craft.parts[i]["def"] as PartDef).radial:
			return i
	return -1


func _on_add_part(def: PartDef) -> void:
	if craft.parts.is_empty():
		if def.category != "command":
			_status.text = "start with a command pod"
			return
		craft.add_part(def)
	else:
		craft.add_part(def, _last_stack_index())
	_rebuild_preview()


func _on_undo() -> void:
	if craft.parts.is_empty():
		return
	var last: int = craft.parts.size() - 1
	var parent_idx: int = craft.parts[last]["parent"]
	if parent_idx >= 0:
		craft.parts[parent_idx]["children"].erase(last)
	craft.parts.remove_at(last)
	_rebuild_preview()


func _on_clear() -> void:
	craft = Craft.new()
	craft.craft_name = _name_edit.text
	_rebuild_preview()


func _on_default() -> void:
	craft = GameState.default_craft()
	_name_edit.text = craft.craft_name
	_rebuild_preview()


func _craft_path() -> String:
	return "user://crafts/%s.json" % _name_edit.text.validate_filename()


func _on_save() -> void:
	craft.craft_name = _name_edit.text
	DirAccess.make_dir_recursive_absolute("user://crafts")
	var f := FileAccess.open(_craft_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(craft.to_dict(), "  "))
	f.close()
	_status.text = "saved: " + _craft_path()


func _on_load() -> void:
	if not FileAccess.file_exists(_craft_path()):
		_status.text = "no such craft: " + _craft_path()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_craft_path()))
	craft = Craft.from_dict(data, GameState.catalog)
	_name_edit.text = craft.craft_name
	_rebuild_preview()
	_status.text = "loaded " + craft.craft_name


func _on_launch() -> void:
	var has_engine := false
	for p: Dictionary in craft.parts:
		if (p["def"] as PartDef).is_engine():
			has_engine = true
	if craft.parts.is_empty() or not has_engine:
		_status.text = "craft needs a pod and at least one engine"
		return
	craft.craft_name = _name_edit.text
	GameState.current_craft = craft
	get_tree().change_scene_to_file("res://flight.tscn")


func _rebuild_preview() -> void:
	for c in _preview.get_children():
		c.queue_free()
	for p: Dictionary in craft.parts:
		var def: PartDef = p["def"]
		var mesh := CylinderMesh.new()
		mesh.height = def.height
		mesh.top_radius = def.diameter * 0.5
		mesh.bottom_radius = def.diameter * 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FlightAssembly.CATEGORY_COLORS.get(def.category, Color.WHITE)
		mi.material_override = mat
		mi.position = Vector3(0.75 if def.radial else 0.0, p["y"], 0.0)
		_preview.add_child(mi)
	_update_stats()


func _update_stats() -> void:
	if craft.parts.is_empty():
		_stats.text = "\nempty craft — add a command pod\n"
		return
	var lines: Array[String] = []
	lines.append("")
	lines.append("parts: %d    mass: %.1f t" % [craft.parts.size(), craft.total_mass() / 1000.0])
	var stages := craft.stage_deltav()
	for i in stages.size():
		var s: Dictionary = stages[i]
		var twr: float = (s["thrust"] / (s["mass"] * VERIDIA_G)) if s.has("thrust") else 0.0
		lines.append("stage %d:  dv %4.0f m/s   TWR %.2f" % [i + 1, s["dv"], twr])
	lines.append("total dv: %.0f m/s" % craft.total_deltav())
	lines.append("")
	_stats.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_cam_dist = maxf(_cam_dist * 0.85, 4.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_cam_dist = minf(_cam_dist * 1.18, 60.0)
	elif event is InputEventMouseMotion and _dragging:
		_cam_yaw -= event.relative.x * 0.006
		_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.006, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _process(_delta: float) -> void:
	# Orbit the middle of the stack.
	var mid_y := 0.0
	if not craft.parts.is_empty():
		var lo := INF
		var hi := -INF
		for p: Dictionary in craft.parts:
			lo = minf(lo, p["y"])
			hi = maxf(hi, p["y"])
		mid_y = (lo + hi) * 0.5
	var basis := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0))
	_cam.position = Vector3(0, mid_y, 0) + basis * Vector3(0, 0, _cam_dist)
	_cam.transform.basis = basis
