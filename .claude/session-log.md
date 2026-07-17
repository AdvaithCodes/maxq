# Session Log

## Current status
All foundational decisions made and recorded in `docs/adr.md`:
- ADR-001: Godot 4.6+ single-precision + floating origin + Jolt + custom
  double-precision orbital math; GDScript with C#/GDExtension hot paths.
- ADR-002: full-3D KSP-like scope, phased roadmap (plan §5).
- ADR-003: stylized low-poly art + rich lighting/atmosphere shaders.
Public repo: https://github.com/AdvaithCodes/maxq
(working title "Max-Q"; local folder is still ~/code/rockets).

Phase 0 spikes BUILT (2026-07-17), all headless checks pass on the M4
(Godot 4.7.1 installed at ~/Applications/Godot.app, no admin needed):
- S1 orbit/floating-origin: all math tests pass (see spikes/README.md).
- S2 planet LOD: builds/benches clean; needs VISUAL run for fps/cracks/jitter.
- S3 Jolt stack: passes with welded-stage design; joint-chain design buckles
  (recorded in learnings — will become an ADR in Phase 2).
Owner benchmark: "if we get something like KSA / Juno: New Origins, we are good."

## Last completed (2026-07-16)
- Owner confirmed engine (Godot), scope (full 3D), art style (low-poly + shaders),
  delegated language choice; wrote ADR-001/002/003 in `docs/adr.md`.
- Deep-dive research: KSP 1/2, Juno: New Origins, Kitten Space Agency (BRUTAL),
  Orbiter, SFS — see `docs/plan.md` §1.
- Stack evaluation across Godot / Unity / Bevy / web / custom → recommendation and
  limitations in `docs/plan.md` §3–4.
- Hardware strategy: M4 Air = primary dev; Intel MBP + Dell = min-spec test rigs.
- Created `docs/plan.md`, this file, `.claude/learnings.md`.

## Next steps (START HERE next session)
Phase 2 in progress. Done so far: part catalog (data/parts.json, 9 parts),
Craft data model (src/craft/) with staging/assembly split per ADR-004,
delta-v + TWR analysis, save/load roundtrip — 14 tests in tests/test_craft.gd.

Build order for the rest of Phase 2 (see docs/roadmap.md Phase 2):
1. VAB scene (vab.tscn): part catalog list UI, click to stack parts, staging
   list display, live dv/TWR readout (Craft.stage_deltav/launch_twr are done,
   just call them). Save craft JSON to user://crafts/.
2. FlightAssembly: Craft.assemblies() -> welded RigidBody3D per group
   (compound cylinder shapes from part height/diameter, summed mass), joints
   at decouplers, collision exceptions (pattern proven in spikes/s3_vessel).
3. Launch scene: flat pad first (planet terrain comes Phase 3), gravity from
   Veridia body data, engine thrust + fuel drain (isp from parts), staging
   key, simple drag. Then: pack to rails when above atmosphere (reuse Vessel).
4. Navball + flight HUD after that.

## Milestones
- v0.1 tagged 2026-07-17: M1 orbital core (owner flew Cinder encounter).

Other pending: Dell run of spikes (reduced-preset check, informational).

## Phase 1 status (2026-07-17)
Root project = orbital core, all 15 sim tests pass headless:
- src/core: DVec3, Kepler (universal-variable propagator + orbit_info).
- src/sim: OrbitElements (full Keplerian, Y-up), CelestialBody hierarchy,
  Universe (loads data/system.json — star Helion, home planet Veridia,
  moons Cinder/Thessa, planets Cindra/Rusk), Vessel (generalized SOI walk,
  node execution), Trajectory (patched-conics predictor, KSP-style
  parent-relative patch rendering), ManeuverNode.
- src/ui: MapCamera (orbit rig), OrbitRenderer (focus-relative, doubles).
- main.gd: warp ladder to 1e6, Tab focus cycle, node editing keys.
- Known minor: CelestialBody parent<->children RefCounted cycle leaks at
  exit (benign, single universe; fix with weakref someday).

## Known/open issues
- None yet (no code). Key risks are recorded as limitations in plan §4 and
  gotchas in `.claude/learnings.md`.
