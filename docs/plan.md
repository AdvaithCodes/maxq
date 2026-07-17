# Project Plan — "Max-Q" (working title)

A Kerbal Space Program–style game: build rockets from parts, launch them, fly real(ish)
orbital mechanics around a fictional solar system, land on other bodies.

Status: **all foundational decisions made** (see `docs/adr.md`): Godot 4.6+, full-3D
scope, GDScript + hot-path escape hatches, stylized low-poly + rich shaders.
Next up: git init, install Godot, Phase 0 spikes.
Last updated: 2026-07-16 (initial research run + owner decisions).

---

## 1. What we're aiming for (genre research)

### The reference games

| Game | Tech | Takeaway for us |
|---|---|---|
| **KSP 1** (2011–) | Unity + PhysX, single-precision | The blueprint. Proved the genre works with *approximated* physics (patched conics, small physics bubble). Ran on very weak hardware. |
| **KSP 2** (2023, cancelled 2024) | Unity | Cautionary tale: overambitious scope (interstellar, colonies, multiplayer) before the core loop was solid; shipped at <20 FPS; ~$50–60M spent, studio shut down. **Lesson: nail the core loop first, scope ruthlessly.** |
| **Juno: New Origins** (SimpleRockets 2) | Unity 2022 | Full 3D KSP-like that runs on Core 2 Duo / 3GB RAM / DX11 iGPU and on phones. **Existence proof that this genre does NOT need a strong GPU.** |
| **Kitten Space Agency** (in dev, RocketWerkz + KSP's original creator) | Custom "BRUTAL" framework (Vulkan, data-oriented) | The serious successor. They went custom because scene-graph engines fight solar-system scale — but they're a funded pro team. Free pre-alpha exists; **play it for research.** |
| **Orbiter** (2000–, open source) | Custom C++/D3D | Hardcore realism end of the spectrum; no vehicle building. |
| **Spaceflight Simulator / SFS** | Unity, 2D | Shows a 2D scope-reduced version is also a beloved game. |
| Children of a Dead Earth, Flyout, Reentry | various | Niche: combat realism / plane building / cockpit realism. |

### What actually makes a KSP-like (core loop)

1. **Build** — part catalog, tree-structured craft assembly, staging, mass/thrust/Δv feedback.
2. **Fly** — launch under full physics near the craft; gravity turn; cut to orbit.
3. **Navigate** — map view, patched-conic trajectory prediction, maneuver nodes, time warp.
4. **Arrive** — SOI transitions, landing on terrain, return. Failure is funny, not punishing.

### The three technical pillars (this is where KSP-likes live or die)

1. **Scale/precision** — a solar system is ~10¹¹ m wide; 32-bit floats have ~7 digits.
   KSP's solution (industry standard, confirmed): keep the engine in **single precision**,
   use a **floating origin** ("Krakensbane": world shifts so the active vessel stays near
   0,0,0 and near-zero velocity), and run orbital state in **double precision on the CPU**.
   → We do NOT need a double-precision engine build.
2. **Two physics regimes** — "on rails" (Kepler/patched conics, analytic, cheap, works at
   100,000× time warp) for everything far away; a full rigid-body **physics bubble**
   (~2 km in KSP) only around the active vessel. The hard part is clean handoff between them.
3. **Planet rendering** — quadtree/chunked-LOD cube-sphere terrain, generated procedurally,
   streamed as you descend from orbit to surface. Plus atmosphere scattering shader.

---

## 2. Hardware reality

| Machine | Specs | Role |
|---|---|---|
| M4 MacBook Air | 16 GB, Apple GPU, ~50 GB free | **Primary dev machine.** M4 GPU is genuinely good; Godot has a native Metal backend on Apple Silicon. Small editor footprint matters for the 50 GB. |
| 2019 Intel MBP | 64 GB, iGPU | Low-end perf test rig #1; heavy asset bakes if ever needed (RAM). |
| Dell Inspiron 3880 | 32 GB, Intel iGPU (UHD 630-class) | Windows test target / low-end perf rig #2. |

Consequences:
- **Unreal is out** (agreed): editor alone ~40–60 GB, needs a dGPU to iterate comfortably.
- Two of three machines are Intel iGPUs → target **stylized low-poly/PBR art**, not
  photorealism; keep a low-spec render path working at all times (Juno proves it's enough).
- Min-spec discipline from day 1: if it doesn't run on the Dell, it doesn't ship.

## 3. Stack options considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Godot 4.6+** | Free/MIT, ~150 MB editor (storage!), native Metal on M4, Jolt physics built-in (4.6), Compatibility renderer for iGPUs, GDScript for fast iteration + C#/GDExtension for hot paths, huge community | Fewer big-3D battle scars than Unity; Forward+ features (SDFGI, volumetrics) too heavy for iGPUs (don't use them); double-precision builds are DIY (we avoid via floating origin) | **✅ Recommended** |
| Unity 6 | Genre-proven (KSP, Juno, Flyout all Unity), best asset/tutorial ecosystem | 10–15 GB install (M4 storage pain), licensing/trust history, heavier editor on 16 GB RAM, closed source | Fallback if Godot hits a wall |
| Bevy (Rust) | `big_space` solves precision elegantly, great perf ceiling, modern ECS | No editor, young/churning API, Rust learning curve on top of game-dev learning curve | Only if we crave Rust |
| Three.js/Babylon (web) | Instant start, runs everywhere | Everything hand-rolled (physics, LOD, save system), JS perf ceiling for terrain gen, not a "shippable game" path | No |
| Custom engine (KSA route) | Perfect fit possible | Multi-year effort by a funded team of specialists | No (solo/small team) |

## 4. Recommended stack (pending sign-off)

- **Engine:** Godot 4.6.x stable, standard official single-precision build.
- **Renderer:** Forward+ (Metal) on the M4; **Compatibility (GL) profile kept working** for
  the Intel machines. Stylized art direction sized for the weakest GPU.
- **Local physics:** Jolt (built into Godot 4.6) — rigid-body sim only inside the physics
  bubble around the active vessel (parts, joints, collisions, landing legs).
- **Orbital mechanics:** custom code, double precision on CPU (GDScript scalar floats are
  already 64-bit; Vector3 is 32-bit — keep orbit state in our own structures). Kepler
  propagation + patched conics + SOI handoff. Craft "on rails" except in the bubble.
- **Scale handling:** floating origin (shift world when active vessel drifts ~ km from
  origin) + per-SOI reference frames. No double-precision engine build.
- **Terrain:** quadtree chunked-LOD cube-sphere, procedural noise heightfields, chunk
  meshing on background threads (or compute on capable GPUs).
- **Languages:** GDScript first for velocity; move measured hot paths (orbit propagation
  batches, terrain meshing) to C# or GDExtension (C++/Rust) only when profiling says so.
- **Version control:** git + GitHub from day 1.

### Known limitations of this choice
- We give up Unity's asset-store shortcuts and its KSP-modding folklore.
- No photorealistic sky/clouds/GI — iGPU budget + Compatibility path forbid it.
- Physics bubble = no long-range rigid-body interactions (identical to KSP; genre-accepted).
- GDScript is slow for numeric crunching — the plan explicitly budgets for hot-path ports.
- Godot Metal backend is Apple-Silicon-only; the Intel MBP runs MoltenVK/GL paths.

## 5. Roadmap (phased, KSP2-lesson-compliant)

> Summary only — the detailed plan (milestones, acceptance criteria, architecture
> modules, perf budgets, risks, timeline) lives in **`docs/roadmap.md`**.

- **Phase 0 — Feasibility spikes (throwaway code):**
  a) floating-origin + on-rails orbit demo (dot orbiting a planet, time warp, SOI switch);
  b) cube-sphere quadtree LOD planet you can fly from orbit to surface;
  c) Jolt stack-of-parts physics toy. Run all three on the Dell/Intel MBP → go/no-go.
- **Phase 1 — Orbital core:** map view, Kepler propagation, patched conics, maneuver
  nodes, time warp. (A "orbit simulator" that's fun to poke at.)
- **Phase 2 — Build & fly:** part catalog, tree assembly VAB, staging, thrust/fuel/mass,
  simple drag; launch a rocket from pad to stable orbit. **This is the vertical slice.**
- **Phase 3 — Planets:** terrain landing, second celestial body, transfer + land + return.
- **Phase 4 — Game:** contracts/career or sandbox polish, science, sound, UI, save games.
- Scope cuts already made: no multiplayer, no interstellar, no colonies, no life support.

## 6. Open questions (owner)

1. ~~Engine~~ → **Godot 4.6+** (ADR-001).
2. ~~Scope~~ → **Full 3D KSP-like** (ADR-002).
3. ~~Art direction~~ → **stylized low-poly + rich lighting/atmosphere shaders**
   (Astroneer/Outer Wilds formula; ADR-003).
4. ~~Language~~ → **GDScript + C#/GDExtension hot paths** (owner delegated; ADR-001).
