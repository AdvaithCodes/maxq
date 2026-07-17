# Phase 0 Feasibility Spikes

Three standalone Godot 4.7 projects (throwaway code, keeper learnings — see
`docs/roadmap.md` Phase 0 and gate G0). Each must also be run on the Intel
machines before G0 is passed.

Run visually: open the folder in Godot and press play, or:

```sh
alias godot="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
godot --path spikes/s1_orbit      # visual demo
godot --path spikes/s2_planet     # visual demo
godot --path spikes/s3_vessel     # windowed physics test (also runs headless)
```

## S1 — orbit math + floating origin (`s1_orbit/`)

Double-precision universal-variable Kepler propagation, patched-conics SOI
handoff planet↔moon, floating-origin vessel view.
Controls: `,`/`.` warp (1x–100,000x), `V` map/vessel view, `R` reset.

- Automated tests: `godot --headless --path spikes/s1_orbit --script res://tests/test_kepler.gd`
- **Status: ALL PASS on M4** — energy drift 2e-7 over 1000 orbits, SOI handoff
  discontinuity 0 m, hyperbolic + reversibility clean.
- Visual check to do by hand: in vessel view (V) at 100,000x warp, the vessel
  must stay pixel-steady (that's the floating origin working).

## S2 — quadtree LOD cube-sphere planet (`s2_planet/`)

600 km-radius planet, procedural terrain, chunk skirts, camera-relative
rendering at chunk granularity (no jitter at the surface).
Controls: click to capture mouse, WASD/QE fly, wheel speed, F auto-speed.

- Benchmark: `godot --headless --path spikes/s2_planet --script res://tests/bench_build.gd`
- **Status on M4 (headless):** 2.8 ms/chunk build, 2.7 ms steady-state LOD pass
  at 651 chunks. Chunk meshing is the #1 GDExtension-port candidate.
- Acceptance to verify by hand: fly from 100 km to the surface — ≥60 fps M4,
  ≥30 fps Dell, no cracks (skirts), no popping holes, no jitter at the surface.

## S3 — Jolt 50-part vessel stack (`s3_vessel/`)

50 parts as 3 welded stage assemblies with joints at the 2 decoupler
interfaces. Pad stability → thrust → staging under load → sanity.

- Run: `godot --headless --path spikes/s3_vessel` (self-reports PASS/FAIL)
- **Status: ALL PASS on M4** — pad drift 4 cm, tilt 0.6°, physics 1.0 ms/frame.
- **Key finding:** the naive "every part is a rigid body in a joint chain"
  design buckles catastrophically (166° fold at 49 joints) even with Jolt at
  20 velocity / 8 position solver steps. Set `WELDED := false` in
  `test_stack.gd` to reproduce. Vessels must be welded compound bodies with
  joints only at functional separations — this becomes an ADR in Phase 2.
