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

## Next steps
1. Owner runs S1 + S2 visually on the M4 (fps, cracks, jitter at warp), then
   all three spikes on the Dell / Intel MBP → gate G0 go/no-go.
2. After G0: create the real Godot project at repo root; start Phase 1
   (orbital core: time system, body hierarchy from data files, map view,
   maneuver nodes) — see docs/roadmap.md.
3. Phase 2 ADR to write when reached: welded vessel assemblies (from S3).

## Known/open issues
- None yet (no code). Key risks are recorded as limitations in plan §4 and
  gotchas in `.claude/learnings.md`.
