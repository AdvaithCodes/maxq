## A craft: a tree of part instances stacked along Y (v1: linear stack +
## radial attachments). Provides mass/staging/delta-v analysis for the VAB and
## the assembly split for flight physics (ADR-004: rigid groups bounded by
## decouplers become single welded bodies).
class_name Craft
extends RefCounted

## Part instance: { "def": PartDef, "fuel": float, "children": Array,
##   "parent": int (index, -1 for root), "y": float (stack position of center) }
var parts: Array = []
var craft_name := "Untitled Craft"


## A "nose" part has only a bottom attach node (parachute etc): it mounts
## ABOVE its parent instead of below.
static func is_nose(def: PartDef) -> bool:
	return def.attach_top == 0.0 and def.attach_bottom != 0.0 and not def.radial


func add_part(def: PartDef, parent_idx: int = -1) -> int:
	var part := {
		"def": def, "fuel": def.fuel_capacity,
		"parent": parent_idx, "children": [], "y": 0.0,
	}
	parts.append(part)
	var idx := parts.size() - 1
	if parent_idx >= 0:
		parts[parent_idx]["children"].append(idx)
	recompute_layout()
	return idx


## Insert a stack part directly below `parent_idx`: if the parent already has
## a stack child, the new part is spliced between them. Radial/nose parts just
## attach to the parent. Returns the new part's index.
func insert_part(def: PartDef, parent_idx: int) -> int:
	if def.radial or is_nose(def):
		return add_part(def, parent_idx)
	var stack_child := stack_child_of(parent_idx)
	var idx := add_part(def, parent_idx)
	if stack_child >= 0:
		parts[parent_idx]["children"].erase(stack_child)
		parts[stack_child]["parent"] = idx
		parts[idx]["children"].append(stack_child)
		recompute_layout()
	return idx


## The child mounted below parent (non-radial, non-nose), or -1.
func stack_child_of(idx: int) -> int:
	for c: int in parts[idx]["children"]:
		var cdef: PartDef = parts[c]["def"]
		if not cdef.radial and not is_nose(cdef):
			return c
	return -1


## Remove one part; its children are re-parented to its parent (stack splice).
## Removing the root is only allowed when it is the sole part.
func remove_part(idx: int) -> bool:
	if idx == 0:
		if parts.size() > 1:
			return false
		parts.clear()
		return true
	var old_parent: int = parts[idx]["parent"]
	for p: Dictionary in parts:
		if p["parent"] == idx:
			p["parent"] = old_parent
	parts.remove_at(idx)
	# Fix indices shifted by the removal, then rebuild children lists.
	for p: Dictionary in parts:
		if p["parent"] > idx:
			p["parent"] -= 1
		p["children"] = []
	for i in parts.size():
		var pi: int = parts[i]["parent"]
		if pi >= 0:
			parts[pi]["children"].append(i)
	recompute_layout()
	return true


## Recompute every part's stack y position from the tree.
func recompute_layout() -> void:
	if parts.is_empty():
		return
	parts[0]["y"] = 0.0
	_layout_children(0)


func _layout_children(idx: int) -> void:
	var p: Dictionary = parts[idx]
	var pdef: PartDef = p["def"]
	for c: int in p["children"]:
		var cdef: PartDef = parts[c]["def"]
		if cdef.radial:
			parts[c]["y"] = p["y"]
		elif is_nose(cdef):
			parts[c]["y"] = p["y"] + pdef.attach_top - cdef.attach_bottom
		else:
			parts[c]["y"] = p["y"] + pdef.attach_bottom - cdef.attach_top
		_layout_children(c)


func total_mass() -> float:
	var m := 0.0
	for p: Dictionary in parts:
		m += (p["def"] as PartDef).dry_mass + p["fuel"]
	return m


## Split the stack into assemblies (welded rigid groups), bottom-up staging
## order: assemblies[0] is jettisoned first. Boundaries are decouplers; the
## decoupler part stays with the assembly BELOW it (it falls away too).
func assemblies() -> Array:
	if parts.is_empty():
		return []
	# Assign group ids walking root-down; every decoupler starts a new group
	# (which it belongs to — it falls away with the stage below).
	var groups: Array = [[]]
	_assign_group(0, 0, groups)
	# Creation order is top-down (root group first); staging is bottom-first.
	groups.reverse()
	return groups


func _assign_group(idx: int, gid: int, groups: Array) -> void:
	var p: Dictionary = parts[idx]
	if (p["def"] as PartDef).decoupler:
		groups.append([])
		gid = groups.size() - 1
	groups[gid].append(idx)
	for c: int in p["children"]:
		_assign_group(c, gid, groups)


## Per-stage delta-v (m/s), vacuum, bottom stage first. Uses the rocket
## equation per stage: engines and fuel in the burning group, full remaining
## craft mass, then the stage's mass is dropped.
func stage_deltav() -> Array:
	var groups := assemblies()
	var result: Array = []
	# Remaining mass starts as the full craft.
	var masses: Array = []
	var fuels: Array = []
	var thrusts: Array = []
	var flows: Array = []  # kg/s at full throttle
	for g: Array in groups:
		var gm := 0.0
		var gf := 0.0
		var gt := 0.0
		var gflow := 0.0
		for idx: int in g:
			var p: Dictionary = parts[idx]
			var def: PartDef = p["def"]
			gm += def.dry_mass + p["fuel"]
			gf += p["fuel"]
			if def.is_engine():
				gt += def.engine["thrust"]
				gflow += def.engine["thrust"] / (def.engine["isp"] * 9.80665)
		masses.append(gm)
		fuels.append(gf)
		thrusts.append(gt)
		flows.append(gflow)

	var remaining := 0.0
	for m: float in masses:
		remaining += m

	for si in groups.size():
		var thrust: float = thrusts[si]
		var fuel: float = fuels[si]
		if thrust <= 0.0 or fuel <= 0.0:
			result.append({"dv": 0.0, "twr_fn": 0.0, "mass": remaining})
			remaining -= masses[si]
			continue
		var isp_eff: float = thrust / (flows[si] * 9.80665)
		var m0 := remaining
		var m1 := remaining - fuel
		var dv: float = isp_eff * 9.80665 * log(m0 / m1)
		result.append({"dv": dv, "thrust": thrust, "mass": m0})
		remaining -= masses[si]
	return result


func total_deltav() -> float:
	var dv := 0.0
	for s: Dictionary in stage_deltav():
		dv += s["dv"]
	return dv


## Thrust-to-weight ratio of the bottom stage at a body's surface.
func launch_twr(surface_gravity: float) -> float:
	var stages := stage_deltav()
	if stages.is_empty():
		return 0.0
	var s0: Dictionary = stages[0]
	if not s0.has("thrust"):
		return 0.0
	return s0["thrust"] / (s0["mass"] * surface_gravity)


## Serialize to a saveable dictionary.
func to_dict() -> Dictionary:
	var out := []
	for p: Dictionary in parts:
		out.append({
			"def": (p["def"] as PartDef).id,
			"fuel": p["fuel"],
			"parent": p["parent"],
		})
	return {"name": craft_name, "parts": out}


static func from_dict(d: Dictionary, catalog: Dictionary) -> Craft:
	var c := Craft.new()
	c.craft_name = d.get("name", "Untitled Craft")
	for pd: Dictionary in d["parts"]:
		var idx := c.add_part(catalog[pd["def"]], pd["parent"])
		c.parts[idx]["fuel"] = pd["fuel"]
	return c
