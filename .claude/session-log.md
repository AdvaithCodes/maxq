# Session Log

## Current status
All foundational decisions made and recorded in `docs/adr.md`:
- ADR-001: Godot 4.6+ single-precision + floating origin + Jolt + custom
  double-precision orbital math; GDScript with C#/GDExtension hot paths.
- ADR-002: full-3D KSP-like scope, phased roadmap (plan §5).
- ADR-003: stylized low-poly art + rich lighting/atmosphere shaders.
No code written yet. Public repo: https://github.com/AdvaithCodes/maxq
(working title "Max-Q"; local folder is still ~/code/rockets).
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
1. Get owner answers to plan §6; record final stack choice as ADR in `docs/adr.md`.
2. `git init`, install Godot 4.6.x stable on the M4 Air.
3. Phase 0 feasibility spikes (plan §5): floating-origin orbit demo, quadtree LOD
   planet, Jolt parts toy — then go/no-go perf check on the Intel machines.

## Known/open issues
- None yet (no code). Key risks are recorded as limitations in plan §4 and
  gotchas in `.claude/learnings.md`.
