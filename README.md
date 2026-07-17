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

**Phase 1 (orbital core) in progress.** The root project is a playable orbital
sim: data-driven star system (`data/system.json`), on-rails patched-conics
vessel, time warp to 1,000,000x, map view with trajectory prediction across
SOI changes, and maneuver nodes. Run it: open this folder in Godot 4.7+ and
press play. Tests: `godot --headless --path . --script res://tests/test_sim.gd`.

Phase 0 spikes (kept for reference): `spikes/` — gate G0 passed on the M4.
