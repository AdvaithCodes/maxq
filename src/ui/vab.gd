## Vehicle Assembly Building, v2.
## - Catalog grouped by category; click a part to insert it BELOW the selected
##   stack part (splicing into the middle is fine). Radial/nose parts attach
##   directly to the selection.
## - Stack list on the right: click to select; selected part is highlighted
##   in the 3D preview; Delete removes it and splices the stack back together.
## - Live per-stage delta-v/TWR breakdown + build warnings.
extends Node3D

const VERIDIA_G := 3.5316e12 / (600_000.0 * 600_000.0)
const CATEGORY_ORDER := ["command", "utility", "fuel", "engine", "structural", "aero"]

var craft: Craft
var _selected := -1

var _preview: Node3D
var _preview_meshes: Array[MeshInstance3D] = []
var _stats: Label
var _name_edit: LineEdit
var _status: Label
var _stack_box: VBoxContainer
var _saved_box: VBoxContainer

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
	_refresh_all()


func _btn(text: String, size: int, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(handler)
	return b


func _header(text: String, box: Container) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.modulate = Color(1, 1, 1, 0.7)
	box.add_child(l)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# ---- Left: part catalog, grouped by category ----
	var left := PanelContainer.new()
	left.position = Vector2(10, 10)
	var lscroll := ScrollContainer.new()
	lscroll.custom_minimum_size = Vector2(280, 840)
	left.add_child(lscroll)
	var lbox := VBoxContainer.new()
	lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(lbox)
	_header("PARTS  (click = add below selection)", lbox)
	for cat: String in CATEGORY_ORDER:
		var cat_parts: Array = []
		for id: String in GameState.catalog:
			var def: PartDef = GameState.catalog[id]
			if def.category == cat:
				cat_parts.append(def)
		if cat_parts.is_empty():
			continue
		_header(cat.to_upper(), lbox)
		cat_parts.sort_custom(func(a: PartDef, b: PartDef) -> bool:
			return a.dry_mass < b.dry_mass)
		for def: PartDef in cat_parts:
			var b := _btn(_part_label(def), 15, _on_add_part.bind(def))
			b.tooltip_text = _part_tooltip(def)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			lbox.add_child(b)
	canvas.add_child(left)

	# ---- Right: name / stack / stats / actions ----
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-370, 10)
	var rbox := VBoxContainer.new()
	rbox.custom_minimum_size = Vector2(360, 0)
	right.add_child(rbox)

	_name_edit = LineEdit.new()
	_name_edit.text = craft.craft_name
	_name_edit.add_theme_font_size_override("font_size", 17)
	rbox.add_child(_name_edit)

	_header("STACK  (click = select)", rbox)
	var sscroll := ScrollContainer.new()
	sscroll.custom_minimum_size = Vector2(0, 260)
	rbox.add_child(sscroll)
	_stack_box = VBoxContainer.new()
	_stack_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sscroll.add_child(_stack_box)

	var hbox := HBoxContainer.new()
	hbox.add_child(_btn("Delete selected", 15, _on_delete_selected))
	hbox.add_child(_btn("Clear", 15, _on_clear))
	rbox.add_child(hbox)

	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	rbox.add_child(_stats)

	rbox.add_child(_btn("Save craft", 16, _on_save))
	rbox.add_child(_btn("Load default test rocket", 16, _on_default))
	var launch := _btn("LAUNCH", 24, _on_launch)
	rbox.add_child(launch)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rbox.add_child(_status)

	_header("SAVED CRAFT", rbox)
	_saved_box = VBoxContainer.new()
	rbox.add_child(_saved_box)
	_refresh_saved_list()
	canvas.add_child(right)


func _part_label(def: PartDef) -> String:
	if def.is_engine():
		return "%s  %.0f kN" % [def.title, def.engine["thrust"] / 1000.0]
	if def.fuel_capacity > 0.0:
		return "%s  %.0f t fuel" % [def.title, def.fuel_capacity / 1000.0]
	return def.title


func _part_tooltip(def: PartDef) -> String:
	var s := "%s\nmass %.0f kg" % [def.title, def.dry_mass]
	if def.fuel_capacity > 0.0:
		s += "  +%.0f kg fuel" % def.fuel_capacity
	if def.is_engine():
		s += "\nthrust %.0f kN  isp %.0f s" % [def.engine["thrust"] / 1000.0, def.engine["isp"]]
	if def.decoupler:
		s += "\nstage separator"
	return s


func _last_stack_index() -> int:
	for i in range(craft.parts.size() - 1, -1, -1):
		var d: PartDef = craft.parts[i]["def"]
		if not d.radial and not Craft.is_nose(d):
			return i
	return -1


func _on_add_part(def: PartDef) -> void:
	if craft.parts.is_empty():
		if def.category != "command":
			_status.text = "start with a command pod"
			return
		_selected = craft.add_part(def)
	else:
		var parent := _selected if _selected >= 0 and _selected < craft.parts.size() \
				else _last_stack_index()
		_selected = craft.insert_part(def, parent)
	_refresh_all()


func _on_delete_selected() -> void:
	if _selected < 0 or _selected >= craft.parts.size():
		_status.text = "select a part in the stack list first"
		return
	var parent: int = craft.parts[_selected]["parent"]
	if not craft.remove_part(_selected):
		_status.text = "remove the rest of the stack before the pod"
		return
	_selected = clampi(parent, -1, craft.parts.size() - 1)
	_refresh_all()


func _on_clear() -> void:
	craft = Craft.new()
	craft.craft_name = _name_edit.text
	_selected = -1
	_refresh_all()


func _on_default() -> void:
	craft = GameState.default_craft()
	_name_edit.text = craft.craft_name
	_selected = -1
	_refresh_all()


func _craft_path() -> String:
	return "user://crafts/%s.json" % _name_edit.text.validate_filename()


func _on_save() -> void:
	craft.craft_name = _name_edit.text
	DirAccess.make_dir_recursive_absolute("user://crafts")
	var f := FileAccess.open(_craft_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(craft.to_dict(), "  "))
	f.close()
	_status.text = "saved: " + _craft_path()
	_refresh_saved_list()


func _refresh_saved_list() -> void:
	for c in _saved_box.get_children():
		c.queue_free()
	var dir := DirAccess.open("user://crafts")
	if dir == null:
		return
	for file: String in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var b := _btn(file.trim_suffix(".json"), 15, _load_file.bind(file))
		_saved_box.add_child(b)


func _load_file(file: String) -> void:
	var path := "user://crafts/" + file
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	craft = Craft.from_dict(data, GameState.catalog)
	_name_edit.text = craft.craft_name
	_selected = -1
	_refresh_all()
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


## ---- refresh: stack list, preview, stats ----

func _refresh_all() -> void:
	_refresh_stack_list()
	_rebuild_preview()
	_update_stats()


func _refresh_stack_list() -> void:
	for c in _stack_box.get_children():
		c.queue_free()
	# Display in visual order: top of rocket first.
	var order: Array = range(craft.parts.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return craft.parts[a]["y"] > craft.parts[b]["y"])
	for i: int in order:
		var def: PartDef = craft.parts[i]["def"]
		var prefix := ""
		if def.radial:
			prefix = "  + "
		elif Craft.is_nose(def):
			prefix = "  ^ "
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = (i == _selected)
		b.text = prefix + def.title
		b.add_theme_font_size_override("font_size", 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_select.bind(i))
		_stack_box.add_child(b)


func _on_select(idx: int) -> void:
	_selected = idx
	_refresh_stack_list()
	_rebuild_preview()


func _rebuild_preview() -> void:
	for c in _preview.get_children():
		c.queue_free()
	_preview_meshes.clear()
	for i in craft.parts.size():
		var p: Dictionary = craft.parts[i]
		var def: PartDef = p["def"]
		var mesh := CylinderMesh.new()
		mesh.height = def.height
		if def.is_engine():
			# Engine bell: narrow at top, flared at the nozzle.
			mesh.top_radius = def.diameter * 0.3
			mesh.bottom_radius = def.diameter * 0.5
		else:
			mesh.top_radius = def.diameter * 0.5
			mesh.bottom_radius = def.diameter * 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FlightAssembly.CATEGORY_COLORS.get(def.category, Color.WHITE)
		if i == _selected:
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.75, 0.1)
			mat.emission_energy_multiplier = 0.6
		mi.material_override = mat
		mi.position = Vector3(0.75 if def.radial else 0.0, p["y"], 0.0)
		_preview.add_child(mi)
		_preview_meshes.append(mi)
	_auto_frame()


func _auto_frame() -> void:
	if craft.parts.is_empty():
		_cam_dist = 14.0
		return
	var lo := INF
	var hi := -INF
	for p: Dictionary in craft.parts:
		var def: PartDef = p["def"]
		lo = minf(lo, p["y"] - def.height * 0.5)
		hi = maxf(hi, p["y"] + def.height * 0.5)
	_cam_dist = clampf((hi - lo) * 1.5 + 4.0, 8.0, 60.0)


func _update_stats() -> void:
	if craft.parts.is_empty():
		_stats.text = "\nempty craft — add a command pod\n"
		return
	var lines: Array[String] = []
	lines.append("")
	lines.append("parts: %d    mass: %.1f t" % [craft.parts.size(), craft.total_mass() / 1000.0])
	var stages := craft.stage_deltav()
	var groups := craft.assemblies()
	for i in stages.size():
		var s: Dictionary = stages[i]
		var twr: float = (s["thrust"] / (s["mass"] * VERIDIA_G)) if s.has("thrust") else 0.0
		lines.append("stage %d (%d parts):  dv %4.0f m/s   TWR %.2f" % [
			i + 1, groups[i].size(), s["dv"], twr])
	lines.append("total dv: %.0f m/s" % craft.total_deltav())
	# Build warnings.
	var has_chute := false
	for p: Dictionary in craft.parts:
		if not (p["def"] as PartDef).parachute.is_empty():
			has_chute = true
	if not has_chute:
		lines.append("! no parachute — landing will be exciting")
	if not stages.is_empty() and stages[0].has("thrust"):
		var twr0: float = stages[0]["thrust"] / (stages[0]["mass"] * VERIDIA_G)
		if twr0 < 1.05:
			lines.append("! launch TWR < 1.05 — it will not lift off")
	if craft.total_deltav() < 3400.0:
		lines.append("! < 3400 m/s dv — orbit is unlikely")
	lines.append("")
	_stats.text = "\n".join(lines)


## ---- camera ----

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
