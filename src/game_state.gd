## Autoload: carries state across scene switches (VAB -> flight -> map).
extends Node

var catalog: Dictionary = {}          # part id -> PartDef
var current_craft: Craft = null       # blueprint being built / flown
## Set by the flight scene when packing to rails; consumed by the map scene.
## {parent: String, r: DVec3, v: DVec3}
var pending_vessel: Dictionary = {}
## Set by the map scene on atmosphere entry; consumed by the flight scene.
## {r: DVec3, v: DVec3} (planet-centered)
var pending_flight_state: Dictionary = {}
## FlightAssembly.snapshot() — staging/fuel state that survives rails trips.
var flight_snapshot: Dictionary = {}


func _ready() -> void:
	catalog = PartDef.load_catalog()


## The classic two-stage test rocket (also used by headless tests).
func default_craft() -> Craft:
	var c := Craft.new()
	c.craft_name = "Test Bird"
	var pod := c.add_part(catalog["pod_mk1"])
	c.add_part(catalog["parachute_mk1"], pod)
	var t1 := c.add_part(catalog["tank_s"], pod)
	var e1 := c.add_part(catalog["engine_sparrow"], t1)
	var d := c.add_part(catalog["decoupler_s"], e1)
	var t2 := c.add_part(catalog["tank_l"], d)
	c.add_part(catalog["engine_kestrel"], t2)
	return c
