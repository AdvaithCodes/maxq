## Headless benchmark: chunk mesh build cost in GDScript.
## Run: godot --headless --path spikes/s2_planet --script res://tests/bench_build.gd
extends SceneTree


func _initialize() -> void:
	var planet: PlanetLOD = PlanetLOD.new()
	get_root().add_child(planet)
	planet._ready()

	var cam := DVec3.new(0.0, 0.0, PlanetLOD.RADIUS + 1000.0)
	var t0 := Time.get_ticks_usec()
	planet.update_lod(cam)  # builds up to BUILDS_PER_FRAME chunks
	var n_frames := 0
	while planet._build_queue.size() > 0 or planet.built_this_frame > 0:
		planet.update_lod(cam)
		n_frames += 1
		if n_frames > 500:
			break
	var t1 := Time.get_ticks_usec()

	var total_chunks: int = planet.chunk_count
	print("built %d chunks in %.1f ms  (%.2f ms/chunk avg incl. LOD pass)" % [
		total_chunks, (t1 - t0) / 1000.0,
		(t1 - t0) / 1000.0 / maxf(1.0, float(total_chunks))])

	# Cost of the per-frame steady-state LOD + reposition pass alone.
	var t2 := Time.get_ticks_usec()
	for i in 60:
		planet.update_lod(cam)
		planet.reposition(cam)
	var t3 := Time.get_ticks_usec()
	print("steady-state LOD+reposition: %.2f ms/frame (%d chunks)" % [
		(t3 - t2) / 1000.0 / 60.0, planet.chunk_count])
	quit(0)
