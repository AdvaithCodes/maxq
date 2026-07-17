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
