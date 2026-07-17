# Architecture Decision Records

## ADR-001: Engine & core stack — Godot 4.6+, single precision, floating origin (2026-07-16)

**Context.** Building a full-3D KSP-like on hardware with no dedicated GPU on 2 of 3
machines (M4 Air 16GB is primary, ~50 GB free disk). Unreal excluded (size/GPU). Genre
requires solar-system scale, two physics regimes, and streamed planet terrain — see
`docs/plan.md` §1. Evaluated Godot, Unity 6, Bevy, web, custom (plan §3).

**Decision.**
- Godot 4.6.x stable, **standard single-precision official build** (no custom engine builds).
- Solar-system scale handled via **floating origin** + per-SOI reference frames +
  **double-precision orbital state in our own CPU-side structures** (KSP's proven approach),
  never engine `Vector3`s.
- **Jolt** (built-in) for rigid-body physics inside the active-vessel bubble only;
  everything else on-rails patched conics.
- Renderer: Forward+ on Apple Silicon; **Compatibility (GL) path kept working always**
  (min-spec = Dell Inspiron iGPU).
  *Amended 2026-07-17 (owner decision):* quality is tuned for the M4 first
  (Forward+/Metal is the primary target); the Intel machines get a reduced
  graphics preset on the Compatibility renderer. "Runs on the Dell" is still
  required — "looks identical on the Dell" is not.
- Language: **GDScript** for game logic; C# or GDExtension (C++) only for hot paths
  that profiling identifies (orbit batch propagation, terrain meshing).

**Consequences.**
- No engine recompiles; official export templates work; upgrades stay cheap.
- All orbital math is ours to write and test (Kepler solver, patched conics, SOI handoff).
- Core visuals restricted to features the Compatibility renderer supports; no SDFGI /
  volumetric fog in the base look.
- If Godot hits an unfixable wall, Unity 6 is the designated fallback (plan §3);
  orbital-mechanics code is engine-agnostic math and would port.

## ADR-002: v1 scope — full 3D KSP-like (2026-07-16)

**Context.** Options were full 3D, 2D-first (SFS-style), or orbit-sim-only first.
KSP2 died from scope creep; but 2D would throw away the build/fly/land 3D core the
owner actually wants.

**Decision.** Full 3D, delivered via the phased roadmap in plan §5 with Phase 0
feasibility spikes and a Phase 2 launch-to-orbit vertical slice as the first real
milestone. Multiplayer, interstellar, colonies, life support are explicitly out.

**Consequences.** Longer road to first playable than 2D; mitigated by phase gates
(go/no-go on Intel-iGPU perf after Phase 0). Scope additions require updating this ADR.

## ADR-003: Art direction — stylized low-poly + rich lighting/atmosphere shaders (2026-07-16)

**Context.** Two of three machines are Intel iGPUs; solo-scale asset authoring; a
KSP-like needs 50–150 parts plus planet terrain. Material/lighting complexity, not
poly count, is what strains iGPUs and authoring time. Reference points: Astroneer /
Outer Wilds / Mars First Logistics (stylized, run everywhere) vs Flyout / KSP2
(semi-real, heavy and unforgiving).

**Decision.** Stylized low-poly assets (simple palettes, minimal texture maps); the
visual "wow" budget goes into shaders: atmospheric scattering, good directional
lighting, simple sky/space rendering. All core visuals must run on the Compatibility
renderer.

**Consequences.** Parts are fast to author (model + palette, no PBR map pipeline);
scenes stay coherent even while unfinished; the orbit money-shot depends on a
one-time atmosphere-shader engineering effort (Phase 3); we accept less
screenshot-realism than semi-real styles.

## ADR-004: Vessels are welded stage assemblies, not per-part joint chains (2026-07-17)

**Context.** Spike S3 measured that a 49-joint chain of rigid bodies buckles
166-175 deg under thrust even with Jolt at 20 velocity / 8 position solver
steps ("noodle rocket"). Welding 50 parts into 3 per-stage compound rigid
bodies with joints only at the 2 decoupler interfaces passed all stability
criteria (0.6 deg tilt, 1 ms/frame).

**Decision.** A craft is a tree of parts (data model), but at flight time each
rigidly-connected group ("assembly", bounded by decouplers/docking ports)
becomes ONE RigidBody3D with compound collision shapes and summed mass
properties. Joints exist only at functional separation interfaces. Adjacent
assemblies get collision exceptions.

**Consequences.** Rock-solid rockets at any part count and trivial physics
cost; per-part flex/breakage is lost (acceptable — KSP's wobble was a bug
players patched away with autostrut, not a feature). Part-level damage, if
ever wanted, is modeled as game logic rather than joint physics.
