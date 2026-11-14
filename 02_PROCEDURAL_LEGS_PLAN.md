# 02 — PROCEDURAL LEGS PLAN (optimized, believable walking)

Goal: legs that look like they really take steps (feet planted, no sliding, natural cadence, stops/turns/jumps/landings), at almost zero cost, on 4 players on weak laptops, **with zero network traffic**.

Starting point: `rig/legs.gd` (phase-based 2-bone IK driving capsule meshes, not wired into `player.tscn`) and `rig_test/body_motion.gd` (bob, lean, landing squash). Claude Code may reuse, rewrite or replace either.

---

## 1. Hard rules

1. **Legs are 100% cosmetic and local.** They read the player's replicated position/velocity and nothing else. **No RPC, no synced state.** Every peer computes the same-looking walk from the same movement data. This is what keeps legs "synced" for free.
2. **Remote players have no real velocity.** `CharacterBody3D.velocity` is not meaningful on remote copies (they lerp toward `_net_pos`). Derive velocity from smoothed position delta there. Local owner may use real velocity. One code path should handle both.
3. **Legs never fight the ragdoll.** On limp begin: legs go inactive and the ragdoll owns the skeleton. On recovery: blend from ragdoll pose to planted feet (see §7).
4. **Budget:** ≤ 0.2 ms per visible player per frame; ≤ 4 raycasts per player per *step* (not per frame); zero per-frame allocations in the hot path.
5. **Testable core.** Gait math lives in a pure `RefCounted` (`GaitMath`, no nodes), like `InputTable`, so it can be unit-tested headless.

## 2. Decision gate: leg style (Claude Code recommends, I approve)

| Style | Look | IK |
|---|---|---|
| **Bird (digitigrade)** | Short hidden thigh, long visible tarsus, joint bends so it reads as backwards, toes on the ground. Fits a chicken best. | 2-bone IK (thigh + tarsus) with the pole/bend direction chosen for the bird look, plus a foot/toe pitch layer |
| Humanoid | Thigh + shin, knee bends forward (what `legs.gd` does now) | 2-bone IK, pole forward |

Default recommendation: **bird**. Whatever is chosen, the rest of this plan is the same.

## 3. Architecture

```
Player
└─ Rig (Node3D)                      ← body scene (Phase 3)
   ├─ Skeleton3D
   │   ├─ Hips … Thigh_L/R → Tarsus_L/R → Foot_L/R
   │   └─ (SkeletonModifier3D IK nodes, if 4.7 provides suitable ones; else our own solver writes bone poses)
   ├─ FootTargets
   │   ├─ FootTarget_L (Marker3D)    ← IK goals; the gait writes these
   │   └─ FootTarget_R (Marker3D)
   └─ LegsController (Node, script: legs_controller.gd)
```

| Piece | Type | Job |
|---|---|---|
| `scripts/gait_math.gd` (`GaitMath`) | RefCounted, static funcs | Pure: stride length from speed, phase advance, step trigger, landing-spot prediction, swing curve, clamp to leg reach |
| `rig/legs_controller.gd` | Node | Reads movement, calls GaitMath, does ground raycasts, writes `FootTarget_*`, handles states/LOD |
| `resources/leg_config.tres` (`LegConfig : Resource`) | Resource | All tunables via `@export` (lengths, stride min/max, swing fraction, step lift, hip drop, ray length, LOD distances). No magic numbers in code |
| IK | Built-in modifier if 4.7 has a usable one (verify; check what `SkeletonModifier3D`-based IK nodes exist), otherwise our two-bone solver (law of cosines, as in `legs.gd _solve`) | Turns foot targets into bone rotations |

## 4. Gait algorithm (recommended: hybrid)

`legs.gd` is purely phase-driven. That looks fine at steady speed but foot-slides on starts, stops, turns and slopes. Recommended hybrid:

1. **Phase clock** (cadence): `phase += speed / stride_length * dt`, left/right offset by 0.5. Stride length lerps between min and max with speed (short quick steps when slow, long when fast). Drives timing and swing curve.
2. **Planted feet are world-locked.** During stance, a foot target does not move at all (this kills sliding).
3. **Step trigger** (safety net on top of phase): if a planted foot gets farther than `max_reach_fraction` of the leg from its hip-projected rest spot (body outran it, turned, or was pushed), force that leg into swing now, if the other leg is planted. Never lift both legs at once while walking.
4. **Landing target:** predict where the body will be at the end of the swing (`pos + vel * swing_time`), offset to the leg's side, plus a forward bias (`STEP_FORWARD_FRACTION`).
5. **Swing curve:** smoothstep forward motion + `sin(PI*t) * lift` vertical arc. Lift scales with speed. (Optional: slight foot pitch for toe-off/heel strike.)
6. **Ground height:** one raycast down at the landing target when a step *begins* (not every frame). Foot Y = hit Y. The plant position is then fixed. Stairs, ledges and slopes work from this alone. Cap max step-up/down; beyond that, leave the foot where the capsule says.
7. **Hip drop / body bob:** pelvis lowers a little with speed and bobs with the phase (reuse `BodyMotion` ideas: bob, lean toward travel direction, landing squash). Bird extra: head-bob counter-motion (head stays steadier than body), small tail wag.
8. **Idle:** feet planted. If body yaw diverges from foot yaw beyond a threshold, take a **turn-in-place step** (re-plant the trailing foot) instead of twisting the ankle.
9. **Stop:** when speed ≈ 0, finish the current swing, then settle the second foot alongside (short "settle step"), no snapping.
10. **Airborne:** feet dangle under hips (slight tuck from vertical velocity). **Landing:** squash + both feet re-plant at the landing spot, with a small raycast.
11. **Teleport/elevator:** detect `speed > TELEPORT_SPEED` or an explicit `reset()` call; instantly re-plant under hips, no streaking legs. (`world.gd` teleports players between rooms, so this matters.)

## 5. Optimization checklist (Claude Code must apply and report)

- **Skip entirely for the owner in first person** if the owner's body stays hidden (`$Body.visible = not mine`). Ask me whether I want visible own legs when looking down; if not, the owner's legs cost 0. (Others still need your legs, so remote copies run it.)
- **LOD by distance/visibility** for remote players: full rate near; reduced update rate (e.g. every 2nd–3rd frame, interpolating) far; frozen pose out of view (`VisibleOnScreenNotifier3D`) or beyond a distance. Document thresholds in `LegConfig`.
- **Raycasts:** at step begin only, via `PhysicsDirectSpaceState3D.intersect_ray` with a **reused** `PhysicsRayQueryParameters3D` object and `MASK_WORLD_STATIC | MASK_PROPS` style mask from `physics_layers.gd`. No `RayCast3D` nodes updating every frame.
- **No per-frame allocation:** preallocated typed arrays, cached node refs, reuse query objects, no `Array.append` churn, no string building in the loop.
- **Idle early-out:** if velocity ≈ 0 and feet settled, skip the solver (cheap flag).
- **Only meshes that matter:** if legs are bone-driven, mesh updates are free (skeleton does it). Avoid recomputing capsule transforms by hand if the skeleton can drive meshes via `BoneAttachment3D`.
- **Profile:** use the Godot profiler/monitors and give me numbers before/after (ms per player, ray count per second) on my machine; I paste the results back.

## 6. Multiplayer notes (legs)

- No new RPCs. Remote legs derive speed from interpolated position, so they may lag the owner by a few ticks: acceptable (cosmetic).
- Smooth velocity (exponential smoothing, as `legs.gd` does with `VELOCITY_SMOOTH`) to hide the 60 Hz jitter of `_net_state` interpolation, otherwise remote legs will stutter.
- Lunge (charged punch) is a high-speed burst: cap stride and cadence so legs do not spin like a cartoon, or use a dedicated "lunge" pose.
- Knockdown/limp: `PlayerState.is_limp()` gates the legs on every machine, because limp begin is already replicated by `_net_limb_begin`. Use that existing signal/state; do not add a new one.

## 7. Handoff with the ragdoll (critical seam)

| Moment | Legs action |
|---|---|
| `_apply_limb_begin` | `legs.set_active(false)`; skeleton control passes to `PhysicalBoneSimulator3D` (spec in `03_...` §A) |
| Limp (any phase) | Legs idle; no solving |
| `_apply_recovery(final)` | Compute planted feet under the **authoritative final transform**; blend simulator influence 1→0 over the get-up time while foot targets are placed at those plant points; then `legs.reset(final)` and `set_active(true)` |
| Teleport mid-limp / run reset / disconnect | Single cleanup path (`03_...` G8) re-plants and reactivates |

## 8. Tests (headless, no rendering)

`tests/test_gait.gd` + `.tscn`, added to `run_checks.ps1`:
1. Steady walk: step count ≈ distance / stride within tolerance.
2. A planted foot's world position changes by 0 across its whole stance.
3. Max foot speed during swing is bounded.
4. Never both feet in swing at once at walking speed.
5. Start from rest, stop from speed, 180° turn: no NaN, no foot farther than leg reach from hip.
6. Teleport: feet under hips next tick.
7. Ground raycast on a step down and a step up: foot Y matches ground, within the step cap.
8. Idle early-out really skips the solver (counter).

## 9. Phases

- **L0 Audit + style decision** (bird/humanoid), check what IK nodes 4.7 offers.
- **L1 `GaitMath` + tests** (pure code first).
- **L2 Skeleton legs + IK + foot targets** in the body scene (I build the bones per EDITOR TASK cards).
- **L3 Walk/stop/turn/idle** with visual debug (draw foot targets, plant points, reach circles; toggle key via InputMap action).
- **L4 Ground raycasts, stairs/slopes, air/landing, teleport reset.**
- **L5 Optimization pass** (LOD, early-outs, profiler numbers).
- **L6 Ragdoll handoff** (limp in/out, get-up) + multiplayer check with 2 instances: remote legs look right, no foot sliding, no pops on teleport.

Each phase ends with the usual: tests, playtest checklist, docs, commit.
