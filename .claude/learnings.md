# Learnings

Gotchas and corrected assumptions. Read early each session; don't re-learn these.

## From the 2026-07-16 research run (assumptions pre-empted)

- **Don't build double-precision Godot.** First instinct for solar-system scale is a
  `precision=double` engine build — it requires compiling the engine AND export
  templates from source, is poorly tested, and extensions must match. KSP itself ships
  single-precision + floating origin + CPU-side double orbital math. Do that instead.
- **GDScript scalar `float` is 64-bit, but `Vector3` is 32-bit** (in standard builds).
  Orbital state must live in our own double structures / scalar math, never engine
  Vector3s, or precision silently degrades.
- **Godot's Forward+ renderer can be rough on Intel iGPUs** (Dell, 2019 MBP). Keep the
  Compatibility (GL) renderer path working from day 1; don't adopt Forward+-only
  features (SDFGI, volumetric fog) in core visuals.
- **Godot's Metal backend is Apple-Silicon-only.** The 2019 Intel MBP falls back to
  MoltenVK/GL. Don't debug "Metal issues" on that machine — it never uses Metal.
- **Physics only in a bubble.** Rigid-body sim (Jolt) applies only within ~2 km of the
  active vessel; everything else is on-rails Kepler. Don't try to physics-sim distant
  craft — KSP's 2.25 km bubble is the genre-proven pattern (Krakensbane).
- **KSP2 died from scope, not tech alone.** Any "wouldn't it be cool if" feature
  (multiplayer, interstellar, colonies) is out until the Phase 2 vertical slice ships.

## From building the Phase 0 spikes (2026-07-17)

- **GDScript has no `%e` format specifier** — it errors at runtime ("unsupported
  format character") but the surrounding code keeps going. Use
  `String.num_scientific()` for scientific notation.
- **Plain Newton fails on the universal Kepler equation for hyperbolic orbits** —
  two distinct failure modes: NaN from `exp()` overflow in Stumpff functions far
  from the root, and "creep" (F grows exponentially, so Newton advances in
  fixed-size steps and exhausts iterations). Fix: bracketed rtsafe-style Newton
  (F is monotonic; map non-finite F to signed INF). Symptom if it regresses:
  vessel teleports to absurd coordinates right at high time-warp or SOI entry.
- **The noodle rocket is real and unfixable with joint chains** (S3, measured):
  49 chained Jolt joints buckle 166–175° under thrust even with velocity_steps=20,
  position_steps=8. Welding parts into per-stage compound rigid bodies (joints
  only at decouplers) passes with 0.6° tilt at 1 ms/frame. Also: attached
  assemblies need `add_collision_exception_with` or contacts fight the joints.
- **Quadtree LOD must memoize chunk centers** — recomputing them each frame
  means noise samples + allocations for every visited node and dominated the
  steady-state cost (4.65 → 2.69 ms/frame after caching). Also gate the whole
  LOD pass on camera movement.
- **Godot 4 `.gitignore` must NOT ignore `*.import`** (that's Godot 3 advice);
  the sidecar `.import` files must be committed or imports break on clone.

## From owner's visual test of the spikes (2026-07-17)

- **Owner directive (supersedes "min-spec first-class" framing):** maximize
  quality on the M4 (Forward+/Metal) within reasonable build effort, THEN scale
  down to the Dell via graphics presets. Don't design visuals down to the iGPU.
- **Extreme camera far/near ratios break Godot's light culler** — far=4e6 with
  near=0.05 spams `create_frustum_points ... rendering_light_culler.cpp` errors
  every frame. Fix: sane near/far per view + scaled-space rendering for distant
  bodies (draw them closer & smaller at the same angular size) instead of a
  multi-million-unit far plane.
- **Depth precision causes black speckle artifacts on planet terrain at
  distance** — the Compatibility renderer has NO reversed-Z (Forward+/Mobile
  gained it in Godot 4.3). Use altitude-scaled dynamic near/far, and prefer
  Forward+ on capable machines.
- **Chunk-edge normals need a ghost ring** — computing normals from one-sided
  differences at chunk borders makes lighting discontinuities (visible seams /
  odd terminator). Sample one extra vertex beyond the chunk border so edge
  normals use centered differences that match the neighbor chunk.
