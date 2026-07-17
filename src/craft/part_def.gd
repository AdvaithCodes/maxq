## Immutable definition of a part type, loaded from data/parts.json.
class_name PartDef
extends RefCounted

var id: String
var title: String
var category: String
var dry_mass: float
var fuel_capacity: float = 0.0
var height: float
var diameter: float
var attach_top := 0.0       # offset from center; 0 = no top stack node
var attach_bottom := 0.0
var radial := false
var decoupler := false
var engine: Dictionary = {}     # {thrust, isp, gimbal_deg} or empty
var parachute: Dictionary = {}  # {drag_area, deploy_altitude} or empty
var crew := 0


static func from_dict(d: Dictionary) -> PartDef:
	var p := PartDef.new()
	p.id = d["id"]
	p.title = d["title"]
	p.category = d["category"]
	p.dry_mass = d["dry_mass"]
	p.fuel_capacity = d.get("fuel", 0.0)
	p.height = d.get("height", 1.0)
	p.diameter = d.get("diameter", 1.25)
	p.attach_top = d.get("attach_top", 0.0)
	p.attach_bottom = d.get("attach_bottom", 0.0)
	p.radial = d.get("radial", false)
	p.decoupler = d.get("decoupler", false)
	p.engine = d.get("engine", {})
	p.parachute = d.get("parachute", {})
	p.crew = d.get("crew", 0)
	return p


func is_engine() -> bool:
	return not engine.is_empty()


static func load_catalog(path: String = "res://data/parts.json") -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "cannot read " + path)
	var data: Dictionary = JSON.parse_string(text)
	var catalog := {}
	for pd: Dictionary in data["parts"]:
		var def := PartDef.from_dict(pd)
		catalog[def.id] = def
	return catalog
