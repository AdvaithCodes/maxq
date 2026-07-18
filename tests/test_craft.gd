## Headless tests for the Phase 2 craft/part data model.
## Run: godot --headless --path . --script res://tests/test_craft.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	print("=== Max-Q craft tests ===")
	_test_catalog()
	_test_two_stage_rocket()
	_test_roundtrip()
	_test_layout_and_editing()

	if _failures == 0:
		print("\nALL TESTS PASSED")
	else:
		print("\n%d TEST(S) FAILED" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _test_catalog() -> void:
	print("\n[part catalog]")
	var cat := PartDef.load_catalog()
	_check(cat.size() == 9, "9 parts loaded", "(%d)" % cat.size())
	_check((cat["engine_sparrow"] as PartDef).is_engine(), "sparrow is an engine")
	_check((cat["decoupler_s"] as PartDef).decoupler, "decoupler flagged")


## Classic two-stage rocket; delta-v cross-checked by hand with the rocket
## equation.
func _build_two_stage(cat: Dictionary) -> Craft:
	var c := Craft.new()
	var pod := c.add_part(cat["pod_mk1"])                 # 800
	c.add_part(cat["parachute_mk1"], pod)                 # 100 (radial-ish top; fine for the model)
	var t1 := c.add_part(cat["tank_s"], pod)              # 250 + 2000 fuel
	var e1 := c.add_part(cat["engine_sparrow"], t1)       # 500
	var d := c.add_part(cat["decoupler_s"], e1)           # 50
	var t2 := c.add_part(cat["tank_l"], d)                # 1000 + 8000 fuel
	c.add_part(cat["engine_kestrel"], t2)                 # 1200
	return c


func _test_two_stage_rocket() -> void:
	print("\n[two-stage rocket analysis]")
	var cat := PartDef.load_catalog()
	var c := _build_two_stage(cat)

	# Total: 800+100+250+2000+500+50+1000+8000+1200 = 13900 kg
	_check(absf(c.total_mass() - 13_900.0) < 0.01, "total mass 13900 kg",
			"(%.1f)" % c.total_mass())

	var groups := c.assemblies()
	_check(groups.size() == 2, "2 assemblies", "(%d)" % groups.size())
	_check(groups[0].size() == 3, "bottom stage: decoupler+tank+engine",
			"(%d parts)" % groups[0].size())
	_check(groups[1].size() == 4, "top stage: pod+chute+tank+engine",
			"(%d parts)" % groups[1].size())

	var stages := c.stage_deltav()
	# Stage 1: Kestrel isp 295, m0 13900, burns 8000 -> m1 5900.
	var dv1_expected := 295.0 * 9.80665 * log(13_900.0 / 5_900.0)
	# After drop (decoupler 50 + tank 1000 + engine 1200 + fuel 8000): m 3650.
	# Stage 2: Sparrow isp 320, m0 3650, burns 2000 -> m1 1650.
	var dv2_expected := 320.0 * 9.80665 * log(3_650.0 / 1_650.0)
	_check(absf(stages[0]["dv"] - dv1_expected) < 0.5, "stage 1 dv correct",
			"(%.1f vs %.1f m/s)" % [stages[0]["dv"], dv1_expected])
	_check(absf(stages[1]["dv"] - dv2_expected) < 0.5, "stage 2 dv correct",
			"(%.1f vs %.1f m/s)" % [stages[1]["dv"], dv2_expected])

	# Launch TWR on Veridia (g = mu/R^2 = 3.5316e12 / 6e5^2 = 9.81).
	var g := 3.5316e12 / (600_000.0 * 600_000.0)
	var twr := c.launch_twr(g)
	var twr_expected := 180_000.0 / (13_900.0 * g)
	_check(absf(twr - twr_expected) < 0.001, "launch TWR correct",
			"(%.2f)" % twr)


func _test_roundtrip() -> void:
	print("\n[craft save/load roundtrip]")
	var cat := PartDef.load_catalog()
	var c := _build_two_stage(cat)
	c.craft_name = "Test Bird"
	var c2 := Craft.from_dict(c.to_dict(), cat)
	_check(c2.craft_name == "Test Bird", "name survives")
	_check(c2.parts.size() == c.parts.size(), "part count survives")
	_check(absf(c2.total_mass() - c.total_mass()) < 1.0e-9, "mass identical")
	_check(absf(c2.total_deltav() - c.total_deltav()) < 1.0e-9, "delta-v identical",
			"(%.1f m/s)" % c2.total_deltav())


func _test_layout_and_editing() -> void:
	print("\n[layout, insert, remove]")
	var cat := PartDef.load_catalog()
	var c := Craft.new()
	var pod := c.add_part(cat["pod_mk1"])
	var chute := c.add_part(cat["parachute_mk1"], pod)
	var tank := c.add_part(cat["tank_s"], pod)
	var engine := c.add_part(cat["engine_sparrow"], tank)

	# Nose part mounts ABOVE the pod (pod top 0.8 + chute half-ish offset).
	_check(c.parts[chute]["y"] > c.parts[pod]["y"], "parachute sits above pod",
			"(y=%.2f)" % c.parts[chute]["y"])
	_check(c.parts[tank]["y"] < 0.0 and c.parts[engine]["y"] < c.parts[tank]["y"],
			"stack descends below pod")

	# Insert a second tank between pod and tank_s: splice.
	var mid := c.insert_part(cat["tank_m"], pod)
	_check(c.parts[tank]["parent"] == mid, "existing tank re-parented to inserted",
			"(parent %d)" % c.parts[tank]["parent"])
	_check(c.parts[mid]["parent"] == pod, "inserted parent is pod")
	_check(c.parts[tank]["y"] < c.parts[mid]["y"], "layout recomputed after insert")
	var mass_before: float = c.total_mass()

	# Remove the inserted tank: splice back, mass restored.
	_check(c.remove_part(mid), "remove succeeds")
	_check(absf(c.total_mass() - (mass_before - 4500.0)) < 0.01,
			"mass restored after remove", "(%.0f kg)" % c.total_mass())
	# Indices shifted: find tank_s again by def id and check its parent is pod.
	var ok_parent := false
	for i in c.parts.size():
		if (c.parts[i]["def"] as PartDef).id == "tank_s":
			ok_parent = c.parts[i]["parent"] == 0
	_check(ok_parent, "stack spliced back to pod after remove")
	_check(not c.remove_part(0), "root pod refuses removal while stack exists")

	# Assemblies/dv still sane after edits.
	_check(c.assemblies().size() == 1, "single stage after edits")
	_check(c.total_deltav() > 1000.0, "dv computable after edits",
			"(%.0f m/s)" % c.total_deltav())