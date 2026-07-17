## Instantiates a Craft blueprint as flight physics per ADR-004: each rigid
## group (bounded by decouplers) becomes ONE RigidBody3D with compound
## collision shapes; joints only at decoupler interfaces; adjacent assemblies
## get collision exceptions. Handles staging, thrust and fuel.
class_name FlightAssembly
extends RefCounted

const CATEGORY_COLORS := {
	"command": Color(0.88, 0.88, 0.9),
	"utility": Color(0.75, 0.55, 0.4),
	"fuel": Color(0.82, 0.78, 0.72),
	"engine": Color(0.35, 0.35, 0.38),
	"structural": Color(0.6, 0.6, 0.62),
	"aero": Color(0.5, 0.65, 0.85),
}

var craft: Craft
var groups: Array = []                 # part-index arrays, bottom-first
var bodies: Array[RigidBody3D] = []    # parallel to groups
var joints: Array = []                 # joints[i] connects groups i and i+1
var fuel: Array[float] = []
var dry_mass: Array[float] = []
var thrust_total: Array[float] = []
var flow_total: Array[float] = []      # kg/s at full throttle
var ignited: Array[bool] = []
var detached: Array[bool] = []
var stage := 0                         # index of the currently-active bottom group
var any_ignited := false
var parachute_deployed := false
var parachute_area := 0.0


## Build bodies/joints as children of parent_node. The stack is placed so its
## lowest point sits at y = clearance above y=0.
func build(p_craft: Craft, parent_node: Node3D, clearance := 1.0) -> void:
	craft = p_craft
	groups = craft.assemblies()

	var min_y := INF
	for p: Dictionary in craft.parts:
		min_y = minf(min_y, p["y"] - (p["def"] as PartDef).height * 0.5)
	var lift := clearance - min_y

	for gi in groups.size():
		var group: Array = groups[gi]
		var g_mass := 0.0
		var g_fuel := 0.0
		var g_dry := 0.0
		var g_thrust := 0.0
		var g_flow := 0.0
		var com_y := 0.0
		for idx: int in group:
			var p: Dictionary = craft.parts[idx]
			var def: PartDef = p["def"]
			var m: float = def.dry_mass + p["fuel"]
			g_mass += m
			g_dry += def.dry_mass
			g_fuel += p["fuel"]
			com_y += m * p["y"]
			if def.is_engine():
				g_thrust += def.engine["thrust"]
				g_flow += def.engine["thrust"] / (def.engine["isp"] * 9.80665)
			if not def.parachute.is_empty():
				parachute_area += def.parachute["drag_area"]
		com_y /= g_mass

		var body := RigidBody3D.new()
		body.mass = g_mass
		body.can_sleep = false
		# Kill Godot's default damping (0.1 linear!) — it acts like hidden air
		# resistance that caps velocity at 10x acceleration. We model real drag.
		body.linear_damp = 0.0
		body.angular_damp = 0.4
		body.position = Vector3(0, com_y + lift, 0)

		for idx: int in group:
			var p: Dictionary = craft.parts[idx]
			var def: PartDef = p["def"]
			var local_y: float = p["y"] - com_y
			var mesh := CylinderMesh.new()
			mesh.height = def.height
			mesh.top_radius = def.diameter * 0.5
			mesh.bottom_radius = def.diameter * 0.5
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = CATEGORY_COLORS.get(def.category, Color.WHITE)
			mi.material_override = mat
			if def.radial:
				# Fins etc: mesh offset to the side, mass only (no collider).
				mi.position = Vector3(0.75, local_y, 0)
				body.add_child(mi)
				continue
			mi.position = Vector3(0, local_y, 0)
			body.add_child(mi)
			var cshape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = def.diameter * 0.5
			cyl.height = def.height
			cshape.shape = cyl
			cshape.position = Vector3(0, local_y, 0)
			body.add_child(cshape)

		parent_node.add_child(body)
		bodies.append(body)
		fuel.append(g_fuel)
		dry_mass.append(g_dry)
		thrust_total.append(g_thrust)
		flow_total.append(g_flow)
		ignited.append(false)
		detached.append(false)

	# Joints at decoupler interfaces + collision exceptions between neighbors.
	for gi in groups.size() - 1:
		bodies[gi].add_collision_exception_with(bodies[gi + 1])
		var dec_y := -INF
		for idx: int in groups[gi]:
			var def: PartDef = craft.parts[idx]["def"]
			if def.decoupler:
				dec_y = craft.parts[idx]["y"] + def.attach_top
		var joint := Generic6DOFJoint3D.new()
		joint.position = Vector3(0, dec_y + lift, 0)
		parent_node.add_child(joint)
		joint.node_a = bodies[gi].get_path()
		joint.node_b = bodies[gi + 1].get_path()
		joints.append(joint)


## The assembly that carries the pod (attitude control authority).
func control_body() -> RigidBody3D:
	return bodies[bodies.size() - 1]


## Live total mass of everything still attached to the control body.
func attached_mass() -> float:
	var m := 0.0
	for gi in bodies.size():
		if not detached[gi]:
			m += bodies[gi].mass
	return m


## Space-bar staging. First press ignites the bottom stage; later presses
## jettison the spent stage and ignite the next. Returns a HUD message.
func do_stage() -> String:
	if not any_ignited:
		any_ignited = true
		ignited[stage] = true
		return "ignition!" if thrust_total[stage] > 0.0 else "staged (no engines)"
	if stage >= groups.size() - 1:
		return "no stages left"
	if stage < joints.size() and is_instance_valid(joints[stage]):
		joints[stage].queue_free()
	bodies[stage].remove_collision_exception_with(bodies[stage + 1])
	detached[stage] = true
	ignited[stage] = false
	stage += 1
	ignited[stage] = true
	return "stage separation"


## Apply engine forces and drain fuel. Called each physics tick.
func apply_thrust(throttle: float, delta: float) -> void:
	if throttle <= 0.0:
		return
	for gi in bodies.size():
		if not ignited[gi] or detached[gi] or fuel[gi] <= 0.0 or thrust_total[gi] <= 0.0:
			continue
		var body := bodies[gi]
		body.apply_central_force(body.global_transform.basis.y * thrust_total[gi] * throttle)
		var dm: float = flow_total[gi] * throttle * delta
		dm = minf(dm, fuel[gi])
		fuel[gi] -= dm
		body.mass = maxf(body.mass - dm, dry_mass[gi])


func current_stage_fuel_fraction() -> float:
	if stage >= groups.size():
		return 0.0
	var cap := 0.0
	for idx: int in groups[stage]:
		cap += (craft.parts[idx]["def"] as PartDef).fuel_capacity
	return fuel[stage] / cap if cap > 0.0 else 0.0


func current_thrust(throttle: float) -> float:
	var f := 0.0
	for gi in bodies.size():
		if ignited[gi] and not detached[gi] and fuel[gi] > 0.0:
			f += thrust_total[gi] * throttle
	return f
