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
Phase 2 VERTICAL SLICE IS PLAYABLE (2026-07-17): VAB -> launch -> fly ->
pack-to-rails -> map view. Full loop: vab.tscn is the main scene; build a
rocket (or "Load default test rocket"), LAUNCH, Space to ignite, fly to
71 km, auto-transition to map. Headless flight autotest:
  godot --headless --fixed-fps 240 --path . res://flight.tscn -- --autotest

Done this session: GameState autoload + scene flow; FlightAssembly (welded
groups per ADR-004, staging, thrust/fuel); flight.gd (central gravity,
Krakensbane w/ origin integration, exp-atmosphere drag, SAS damping, WASD/QE
attitude, throttle, parachute stub, pack-to-rails); VAB (catalog UI, stack
building, live dv/TWR, save/load user://crafts/, launch); map accepts packed
vessel; 45 unit checks + flight autotest green.

Remaining for M2 (v0.2):
1. Owner playtest of the full loop -> fix feel issues (SAS strength, camera,
   drag tuning). SAS is rate-damping only; consider attitude-hold.
2. Navball (the genre's soul — deserves real effort).
3. Landing/splashdown + recovery flow (parachute logic is minimal; no
   surface collision away from pad — needs at least a sea-level kill plane).
4. Reentry from map view back to flight scene (currently one-way to rails).
5. Craft file-browser in VAB (currently load-by-name only).

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
