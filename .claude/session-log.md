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

DONE since (2026-07-17 later): owner flew full run to orbit. Then built:
- Navball (src/ui/navball.gd): shader sphere in SubViewport, prograde/
  retrograde markers, heading readout in HUD.
- Full mission loop closed: map hands back to flight below 68 km when a
  flight_snapshot exists; FlightAssembly snapshot/restore carries staging/
  fuel across rails trips; reentry spawn (_spawn_from_orbit).
- Ground-zone landing system: below 4 km the frame is pinned planet-static
  (frame_vel folded into bodies), dynamic ground slab tracks under the pod,
  touchdown (<0.6 m/s for 2 s) / crash (>15 m/s) detection, [R] recover.
- Chute: arms with P, opens < 1500 m & < 420 m/s (cap = opening shock).
- VAB saved-craft browser.
- New headless reentry autotest: --reentry-test (falls from 60 km, chute,
  soft landing PASS). Ascent autotest + 45 unit checks green.

VAB v2 (2026-07-17): catalog grouped by category with inline stats; stack
list with selection; insert-below-selection with mid-stack splicing;
delete-anywhere (Craft.insert_part/remove_part/recompute_layout, tested);
nose parts (parachute) mount ABOVE parent now; engine-bell preview shapes;
selected-part highlight; auto-framing camera; build warnings (no chute /
TWR < 1.05 / dv < 3400).

Remaining for M2 (v0.2 tag):
1. Owner: fly the FULL round trip (launch -> orbit -> deorbit burn ->
   reentry -> chute -> touchdown -> recover). If good, tag v0.2.
2. Feel tuning from playtest (SAS is rate-damping only; consider
   attitude-hold; camera; control authority).
3. Known gaps: suborbital rails flight doesn't warn before ground impact if
   no craft snapshot (sandbox map start); no map access DURING flight (M key
   someday); single launch site; no crash consequences beyond message.

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
