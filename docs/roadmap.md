# Max-Q — Detailed Development Roadmap

Expands `docs/plan.md` §5. Each phase ends in a **playable build + git tag** and a
phase-gate review (update ADRs/session log; cut or keep scope). Estimates assume
part-time solo dev and are ranges, not promises.

Owner's quality bar: Kitten Space Agency / Juno: New Origins territory.

---

## System architecture (what we're building, by module)

| # | Module | Contents | Notes |
|---|--------|----------|-------|
| 1 | **Core math** (engine-agnostic) | `DVec3` double-vector ops; Kepler orbit (elements ↔ state vectors, Kepler-equation solver); patched-conics propagator; SOI computation; universal time/epoch | Pure GDScript first; the module most likely to move to GDExtension later. Unit-tested hardest. |
| 2 | **Frames & floating origin** | Active-vessel anchor; origin rebase when vessel drifts >~2 km; world↔render transforms; rotating vs inertial frames (surface vs orbit velocity); Krakensbane velocity rebase | The engine sees only small, near-origin floats. |
| 3 | **Simulation** | Vessel (on-rails ↔ active states); physics-bubble manager (pack/unpack Jolt bodies); part-graph → rigid bodies + joints; staging; fuel flow; forces (thrust, gravity, drag) | Physics only inside bubble; everything else rails. |
| 4 | **Celestial bodies** | Body defs (mass/GM, radius, rotation, atmosphere params, orbital elements); system hierarchy config | Data-driven from day 1 (resource files). |
| 5 | **Terrain & space rendering** | Cube-sphere quadtree LOD; procedural noise heightfields; threaded chunk meshing; near-vessel collision meshes; **scaled-space** rendering of distant bodies (KSP's trick); atmosphere scattering shader; skybox | Must run on Compatibility renderer. |
| 6 | **Gameplay/UI** | VAB editor (catalog, attach nodes, symmetry, staging list, Δv/TWR readout); flight UI (navball, altimeter, apo/peri); map view (orbit lines, maneuver nodes); time-warp UI; save/load | Navball is the soul of the genre — budget real time for it. |
| 7 | **Content** | Parts (~25–30 for the slice, 60+ later); home star system (star, home planet, moon, then more) | Stylized low-poly, palette materials (ADR-003). |

## Phase 0 — Feasibility spikes (throwaway code) — ~2–4 weeks

Three isolated Godot projects under `spikes/`. Code is disposable; learnings are not.

- **S1 — Orbit & origin spike:** double-precision Kepler propagation + floating origin.
  *Accept:* circular + elliptic orbits stable over 1000 simulated orbits (energy drift
  < 0.1%); no visual jitter at any warp from 1× to 100,000×; planet→moon SOI handoff
  with < 1 m position discontinuity.
- **S2 — Planet spike:** cube-sphere quadtree LOD with noise terrain.
  *Accept:* continuous descent from 100 km to surface; ≥ 60 fps on M4, ≥ 30 fps on
  the Dell (Compatibility renderer); no cracks between chunks (skirts or stitching).
- **S3 — Vessel physics spike:** Jolt stack of 50 joined rigid bodies.
  *Accept:* stable on pad (no wobble explosion), survives thrust + separation events,
  ≥ 60 fps M4 / ≥ 30 fps Dell.
- **GATE G0:** all three pass on the Intel machines → proceed. Any failure → fix
  approach or reconsider stack (ADR update mandatory). Only after G0: create the real
  Godot project at repo root.

## Phase 1 — Orbital core ("the sim is fun to poke") — ~4–8 weeks

1. Time system: epoch, warp ladder (1× → 100,000×), pause.
2. Celestial hierarchy loaded from data files: star, home planet ("Kerbin-alike",
   ~600 km radius), one moon.
3. Rails propagation + SOI transitions (productionized from S1, with tests).
4. Map view: orbit camera, orbit line rendering, body icons, focus switching.
5. Maneuver nodes: prograde/normal/radial Δv handles, predicted post-burn conic,
   multi-patch preview across SOI changes.
6. Placeholder vessel (a dot with mass) executing impulsive burns.
- **Milestone M1 (tag `v0.1`):** plan and fly transfer → moon capture → return using
  maneuver nodes only. **Test suite:** orbital math vs. textbook two-body cases.

## Phase 2 — Build & fly: THE VERTICAL SLICE — ~2–4 months

1. Part system: part resource format (mass, cost, attach nodes, module data);
   craft = part tree; craft file save/load.
2. VAB: part catalog UI, snap placement on attach nodes, 2×/4× symmetry, staging
   list editor, live Δv/TWR readout (uses core math — reuse, don't duplicate).
3. Physics bubble: instantiate craft as Jolt bodies + joints on pad / unpack from
   rails; repack to rails above atmosphere when idle; floating-origin + velocity
   rebase integrated under thrust.
4. Flight systems: engine thrust + gimbal, fuel drain per stage, staging events
   (decouplers), simple drag model (v1: Cd·A per part, no occlusion), basic SAS
   (PID hold orientation).
5. Flight UI: **navball**, altimeter, apoapsis/periapsis, velocity modes
   (surface/orbit), throttle, stage button, map-view toggle mid-flight.
6. Content: ~25–30 parts (pods, tanks ×3 sizes, engines ×4, decouplers, fins,
   legs, parachute), launch pad site, placeholder-but-clean low-poly art.
7. Save/load mid-flight (versioned format from the first save ever written).
- **Milestone M2 (tag `v0.2`):** build in VAB → launch → gravity turn → circularize
  → deorbit → parachute splashdown, on all three machines. *This is the go/no-go
  for the whole project's fun factor. Playtest with 2–3 humans.*

## Phase 3 — Planets & landing — ~2–3 months

1. Productionize S2 terrain: collision meshes near vessel, biome-tinted materials,
   simple surface scatter (rocks).
2. Scaled-space layer for distant bodies (render planets as small far models;
   swap to real terrain on approach).
3. Atmosphere scattering shader (the ADR-003 "wow budget") + height fog;
   reentry VFX (plasma glow — cosmetic only in v1).
4. Landing gameplay: legs, surface stability, EVA-less flag-plant equivalent
   (probe/claim marker), moon gets terrain.
5. Second planet + its SOI reachable.
- **Milestone M3 (tag `v0.3`):** full Mun-style mission — launch, transfer, land on
  moon, return, reenter, recover. Screenshot-worthy from orbit.

## Phase 4 — Game layer & public build — ongoing

1. Progression-lite: pick ONE currency (science or funds), contracts/milestone
   goals, part unlocks. (Sandbox mode always available.)
2. Sound design (engine, staging, ambience, UI) + a few music tracks.
3. Onboarding: 3–4 guided tutorials (orbit, transfer, landing).
4. Settings, rebindable keys, graphics presets (M4 vs iGPU).
5. Perf hardening pass; port profiled hot loops to GDExtension if needed.
- **Milestone M4 (tag `v0.4-public`):** itch.io playtest build + feedback loop.
  Steam page only after playtest signal is good.

## Cross-cutting rules

- **Perf budgets (frame @ 60fps M4 / 30fps Dell):** physics ≤ 4 ms; terrain
  update ≤ 4 ms amortized; UI ≤ 2 ms. Profile on the Dell every phase end.
- **Testing:** GUT (Godot Unit Test) for core math from Phase 1; scenario scenes as
  regression tests (saved situations that must still load & behave).
- **Discipline:** session log updated every session; learnings.md on every corrected
  mistake; ADR before any architecture deviation; milestone = git tag + playable zip.
- **Scope firewall (KSP2 rule):** no multiplayer, interstellar, colonies, life
  support, or resource mining until after M4. Requests go to `docs/icebox.md`.

## Top risks & mitigations

| Risk | Mitigation |
|---|---|
| GDScript too slow for orbit/terrain math | Isolate in Module 1 behind clean API; port to GDExtension (C++) when profiling proves it |
| Jolt joint wobble on tall rockets (KSP's "noodle rocket") | Fewer, stiffer joints; auto-strut-style constraint welding; part-count guidance |
| Quadtree cracks/popping | Chunk skirts first (cheap), stitching only if skirts show |
| Rails↔physics handoff bugs (the Kraken) | Deterministic pack/unpack tests; single authoritative state owner per vessel |
| Compatibility renderer feature gaps discovered late | Dell is a first-class test target at every milestone, not just at the end |
| Solo-dev burnout / scope creep | Phase gates, icebox doc, every phase ends in something playable |

## Rough overall timeline (part-time solo)

Phase 0: weeks 1–4 · M1: ~month 3 · **M2 vertical slice: ~month 6–8** ·
M3: ~month 10–12 · M4 public build: ~month 12–15. Half-speed is fine;
skipping gates is not.
