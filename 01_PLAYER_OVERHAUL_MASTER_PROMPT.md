# 01 — PLAYER OVERHAUL: MASTER PROMPT (for Claude Code)

Drop all three files in `docs/`. Then tell Claude Code:
> "Read `docs/01_PLAYER_OVERHAUL_MASTER_PROMPT.md`, then `02_PROCEDURAL_LEGS_PLAN.md` and `03_RAGDOLL_MULTIPLAYER_AND_TEACHING.md`. Start Phase 0."

Companion files (they are binding, not optional reading):
- `02_PROCEDURAL_LEGS_PLAN.md` — the procedural walking system.
- `03_RAGDOLL_MULTIPLAYER_AND_TEACHING.md` — the **ragdoll network-sync contract** and the **teaching/instruction standard** (Godot + Blender).

---

## 0. PRIME DIRECTIVES (read twice)

1. **MULTIPLAYER IS NEGOTIABLE.** Fowl Play is host-authoritative local multiplayer (ENet, host = peer 1, up to 3 clients). If the ragdoll is not synchronized between Host and Clients, the feature has FAILED, no matter how good it looks on one machine. Every design decision, spike, and slice must be judged against `03_...` section A ("Sync Guarantees G1–G8"). A feature that works only in single player is not done.
2. **TEACHING IS A DELIVERABLE.** I am learning rigging, physical bones, joints and procedural animation. Every editor (and, if unavoidable, Blender) step must follow the standard in `03_...` section B: numbered, exact menu paths, expected result, "if you see X instead", nothing left to guess.
3. **Do not break what works.** Combat, carry, props, rooms, tables, elevator and all existing tests stay green.

## 1. How we work together

I use the **Godot 4.7 Steam editor**. I can build `.tscn` / `.tres`, node hierarchies, attach scripts, create `Skeleton3D` bones, `PhysicalBoneSimulator3D` / `PhysicalBone3D`, collision shapes, layers/masks, inspector values.

- You write the scripts and simple `.tscn`/`.tres` text.
- Anything fiddly (bone rest poses, joint limits, shape sizing, node-by-node scene building) you hand to me as an **EDITOR TASK card**; scripts as **SCRIPT HANDOFF cards** (formats in `03_...` §B).
- **Blender: avoid it.** Prefer an editor-only path (primitive meshes + `BoneAttachment3D`, see `03_...` §B.4). If you judge Blender truly necessary, you must (a) justify it at the Phase-1 decision gate, (b) get my approval, and (c) give a full **BLENDER TASK card** set (`03_...` §B.5). No vague "just rig it in Blender".
- **Explain the why** of each concept the first time it appears: bone hierarchy, rest pose, physical bones, joint types/limits, simulator start/stop, influence/blend, handback.

## 2. Authority

You have full control. Remove, add, rename, restructure or replace anything in the player-facing code, including APIs, scene layout, `rig/legs.gd`, `rig_test/*`, `hands.gd`. Make recommendations and act on them.

Guardrails:
1. **One checkpoint:** after the Phase 0 audit, give me a short plan (decisions + reasons) and **stop for my go**. After that, proceed slice by slice.
2. **Decision gates** (stop and ask): the ragdoll sync approach (after the spike), Blender-or-not, bird vs humanoid legs, camera target. Everything else: decide and document.
3. **Record every decision** in `docs/PLAYER_OVERHAUL.md` (what + why). Keep `BUILD_GUIDE.md` and `COMBAT_MECHANICS.md` in sync (CLAUDE.md rule 10).
4. **Scope override:** `CLAUDE.md` marks `hands.gd` OUT OF SCOPE. For this task that is lifted. Update `CLAUDE.md` and docs to say so.
5. **Networking authority:** you may restructure existing host/client calls per `03_...` §A.9, within its guardrails (sync guarantees, incremental migration, tests first, decision gate before the first networking slice).

## 3. Scope

### Part 1 — Hands → reusable scene-backed component
`player/hands.gd` builds everything procedurally (palm, forearm, 4 fingers × 3 joints, thumb, tweens, curl poses, hover/reach aim math). Refactor into a real `.tscn` with a node hierarchy and attached script.
- Joint pivots, per-hand rig nodes, meshes and materials become **scene nodes / sub-resources / `.tres`**; tunables become `@export` or `PhysicsTuning`.
- **Preserve the public API exactly:** `world_mode` (set before `add_child`), `add_sway`, `set_speed`, `set_color`, `set_guard`, `shake`, `set_hover`, `update_hover_point`, `reach`, `class_name Hands`. Keep both modes (first-person viewmodel on the camera; world model for other players on the head), via one scene + mode switch or inherited scenes, your call.
- Callers to keep working: `player.gd`, `combat.gd` (`hands.set_guard`), `_net_reach`, `_net_hover_state`, `_net_punch_hitbox`, `_net_parry`.
- **Verify, don't assume, these suspected bugs:**
  - `player.gd:_ready` calls `Hands.new()` twice (the first, named "Hands", is discarded).
  - `_net_punch_hitbox` uses `puncher.has_node("Hands")` but hands live under `Head` or `Head/Camera3D`, so remote punch-reach visuals may never run.
  - `_net_parry` uses fallback path guesses; prefer the stored `p.hands` reference everywhere.
  - `_net_hover_point` RPC may be unused.
- Parity first (screenshot-compare like `tests/capture_*.gd`), polish after.

### Part 2 — Body → articulated ragdoll character
Head, torso, legs, plus fowl features (wings, tail, beak) as articulated, physics-capable parts.
- **Skeleton:** design the bone hierarchy with me. Starting proposal (change it if you can justify it):
  `Hips(root) → Spine → Chest → Neck → Head`; `Chest → Wing_L / Wing_R`; `Hips → Tail`; `Hips → Thigh_L/R → Tarsus_L/R → Foot_L/R`.
  Beak is a rigid attachment on Head.
- **Meshes without Blender:** primitive meshes on `BoneAttachment3D` nodes (rigid, no skin weights). See `03_...` §B.4.
- **Physical bones:** `PhysicalBoneSimulator3D` + `PhysicalBone3D`, joint types/limits/masses/damping. The project uses **Jolt Physics**: verify which joint types and properties behave correctly in 4.7 *before* committing to a design (spike).
- **Physical bone budget:** target ≤ 9–10 physical bones per player (e.g. Hips, Chest, Head, Wing×2, Thigh×2, Tarsus×2). They count against the **≤ 20 awake rigid bodies** budget (4 players, weak school laptops). Define a policy for multiple simultaneous ragdolls (e.g. extras fall back to capsule-only + canned flop).
- **Legs:** see `02_PROCEDURAL_LEGS_PLAN.md`.
- **State flow:** normal movement → knockdown/limp (GROUND / CARRIED / THROWN) → recovery. Includes a clean **get-up**: capsule re-snap relative to hips, ground height, pose blend (use simulator `influence` or equivalent, verify in 4.7).
- **Integration (don't break the contracts):** `Player`, `PlayerState`, `BodyPhys` (capsule `RigidBody3D`, dormant until limp, `top_level`, host-simulated, clients interpolate), `CarryRegistry`, `Carrier` (`get_carry_offset`, `pickup`/`release`), camera (`_limp_puppet`; decide capsule vs hips vs head-bone target; avoid jitter and head-clipping), `punch_hitbox.gd` (dedupes by walking up to the peer-id-named root; extra physics bodies under the player must not cause multi-hits or break parry).
- **Layers/masks:** edit **only** `scripts/physics_layers.gd`. Ragdoll bones must hit world and props, must NOT shove other players' capsules, trigger focus rays, or register as punch targets by accident. If a new layer is needed add it there and update the table in `BUILD_GUIDE.md`.

## 4. Technical constraints

- Typed GDScript, Godot 4.7, no `:=` where the compiler errors. InputMap actions only, never raw keycodes.
- `class_name` registration order has bitten this project (see `godot_err.txt`). Use `preload` where needed and tell me when to run the import step (`--editor --import --quit` or reopening the editor).
- Keep node-path contracts unless you update every consumer + test in the same slice and say so: `Players/<id>`, `$Body`, `$Head`, `$Head/Camera3D`, `$BodyPhys`, `$NamePlate`, and the properties `player.hands/head/state/combat/carrier`.
- **Doc/code drift to reconcile while touching the player:** `LIMP_SECONDS` is 3.5 in `physics_tuning.gd` but 2.5 in the `.tres` and docs; `player.gd` re-declares combat constants (`PUNCH_CHARGE_MS`, `LUNGE_SPEED`, etc.) that differ from `PhysicsTuning`; `COMBAT_MECHANICS.md` describes `take_punch`/`parry_riposte` flow that no longer matches the hitbox flow.
- Sandbox: you cannot run Godot or git. I run `./tests/run_checks.ps1` and commit. Tell me exactly what to run and what output to expect.
- Networking rules (unchanged): every `any_peer` RPC validates `get_remote_sender_id()` + state; host owns all timers; never RPC to yourself.

## 5. Process

**Phase 0 — Audit (read-only).** Map the current player scene/nodes; every caller of the Hands API; every consumer of `$Body`/`BodyPhys`/limp state; the limp/carry/camera flow; current RPC list touching limp. List bugs and risks. Deliver the plan. **STOP for my go.**

**Phase 1 — Spikes + decision gates.** (a) Ragdoll sync approach A vs C per `03_...` §A.4, with measurements. (b) Jolt joint behavior. (c) Camera target. (d) Rigging path (editor-only vs Blender). (e) Bird vs humanoid legs. Present results; I decide.

**Phase 2 — Hands scene** (parity first).

**Phase 3 — Body scene + skeleton**, static then animated with procedural legs (no ragdoll yet), per `02_...`.

**Phase 4 — Ragdoll integration**: limp, carry, throw, recovery, get-up, **with the sync contract tests passing**.

**Phase 5 — Multiplayer hardening + cleanup**: the full test matrix in `03_...` §A.7, delete dead code, update docs.

**Every slice ends with:** build → I run `run_checks.ps1` + a 2-instance host/client playtest (you provide the checklist) → fix → docs updated → I commit locally on `features/physics-overhaul-and-mechanics` (message ends `Co-Authored-By: Claude Code <noreply@anthropic.com>`; no push, `reset --hard`, `checkout --`, force push, `clean`, `rm -rf .godot`).

Add/extend headless tests for everything testable (state transitions, handback positions, API parity, gait math, sync tolerances). Keep every existing suite green.

**Start with Phase 0 now.**
