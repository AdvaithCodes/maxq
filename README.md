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

- [`docs/plan.md`](docs/plan.md) — vision, genre research, stack evaluation, roadmap
- [`docs/adr.md`](docs/adr.md) — architecture decision records
- `.claude/session-log.md` — session-to-session status
- `.claude/learnings.md` — gotchas; read before assuming

## Status

Pre-code. Next: Phase 0 feasibility spikes (floating-origin orbit demo, quadtree LOD
planet, Jolt parts toy) — see `docs/plan.md` §5.
