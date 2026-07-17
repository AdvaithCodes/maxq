## Loads and owns the celestial body hierarchy (data-driven from JSON).
class_name Universe
extends RefCounted

var root: CelestialBody
var bodies: Array[CelestialBody] = []
var by_name := {}


static func load_from_json(path: String) -> Universe:
	var text := FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "cannot read " + path)
	var data: Dictionary = JSON.parse_string(text)
	var u := Universe.new()

	for bd: Dictionary in data["bodies"]:
		var b := CelestialBody.new()
		b.body_name = bd["name"]
		b.mu = bd["mu"]
		b.radius = bd["radius"]
		var c: Array = bd.get("color", [1.0, 1.0, 1.0])
		b.color = Color(c[0], c[1], c[2])
		u.bodies.append(b)
		u.by_name[b.body_name] = b

	# Second pass: hierarchy + orbits + SOI.
	for bd: Dictionary in data["bodies"]:
		var b: CelestialBody = u.by_name[bd["name"]]
		if bd.has("parent"):
			b.parent = u.by_name[bd["parent"]]
			b.parent.children.append(b)
			b.orbit = OrbitElements.from_dict(bd["orbit"], b.parent.mu)
			# r_soi = a * (m / M)^(2/5)
			b.soi = b.orbit.a * pow(b.mu / b.parent.mu, 0.4)
		else:
			assert(u.root == null, "multiple root bodies")
			u.root = b
			b.soi = INF
	return u
