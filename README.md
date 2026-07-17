# Max-Q (working title)

A Kerbal Space Program–style game: build rockets from parts, launch them under real
physics, fly patched-conic orbital mechanics around a fictional solar system, and land
on other bodies.

- **Stack:** Godot 4.6+ (single-precision build), Jolt physics (local bubble), custom
  double-precision orbital mechanics with a floating origin. GDScript first.
- **Look:** stylized low-poly + atmospheric scattering / lighting shaders
  (Astroneer / Outer Wilds formula).
- **Min spec is first-class:** must run on an Intel iGPU (Godot Compatibility renderer).

## Docs

- [`docs/plan.md`](docs/plan.md) — vision, genre research, stack evaluation
- [`docs/roadmap.md`](docs/roadmap.md) — detailed development plan (phases, milestones, risks)
- [`docs/adr.md`](docs/adr.md) — architecture decision records
- `.claude/session-log.md` — session-to-session status
- `.claude/learnings.md` — gotchas; read before assuming

## Status

**Phase 2 vertical slice playable**: build a rocket in the VAB, launch it
under real central gravity + drag (welded-assembly Jolt physics, floating
origin), stage, climb above the atmosphere, and hand off to the on-rails map
view with maneuver nodes and time warp. Open this folder in Godot 4.7+ and
press play (starts in the VAB; "Load default test rocket" for a quick start).
Tests: the three scripts in `tests/` plus
`godot --headless --fixed-fps 240 --path . res://flight.tscn -- --autotest`.

Phase 0 spikes (kept for reference): `spikes/` — gate G0 passed on the M4.
