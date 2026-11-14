# 03 — RAGDOLL MULTIPLAYER CONTRACT + TEACHING STANDARD

Two binding parts:
- **Part A:** how the ragdoll stays synchronized between Host and Clients.
- **Part B:** how Claude Code must teach me every Godot (and, if unavoidable, Blender) step.

---

# PART A — RAGDOLL MULTIPLAYER CONTRACT

> If the ragdoll is not in sync between Host and Clients, the feature has failed.

## A.1 What already exists (build on it, don't fight it)

- Host = peer 1, simulates physics. Clients interpolate.
- `BodyPhys` on each player: capsule `RigidBody3D`, dormant until limp, `top_level`, host-simulated. Host sends `_sync_snapshot` (unreliable_ordered, ~15 Hz) and `_sync_settled` (reliable). Clients `_follow_snapshot` (lerp/slerp).
- Limp begin/end are already reliable, host-validated RPCs: `_net_limb_begin(start_pos, launch, seconds)` and `_net_limb_end(final_pos)` (any_peer, sender must be 0 or 1).
- Recovery clock is host-only (`BodyPhys` timer, `limp_recovered`).
- `CarryRegistry` replicates holds (`_rpc_hold_begin/end/launch`) and late-join prop state.

The ragdoll must ride on these. **No second, parallel network system for limp state.**

## A.2 Layers of truth

| Layer | What | Who owns it | Transport |
|---|---|---|---|
| **L1 Events** | limp begin (start transform, launch, seconds, **seed**), phase change (GROUND/CARRIED/THROWN), recovery (final transform + yaw), who carries whom | Host | Reliable RPC (extend existing ones) |
| **L2 Body state** | capsule transform + velocities | Host | Existing `BodyPhys` snapshots |
| **L3 Bone sim** | per-bone physics | Each machine locally (Option A) or host (Option C) | none (A) / pose snapshots (C) |
| **L4 Pose snapshot** | quantized bone poses | Host | unreliable_ordered, low rate, **only if the spike says A is not enough** |

Clients own nothing here. They report intent (punch, grab) as today; they never drive limp, recovery or ragdoll state.

## A.3 Sync Guarantees (acceptance criteria)

- **G1 Same event, same start.** Every peer starts the ragdoll for a given player from the same start transform and the same launch velocity (within one network round trip).
- **G2 Anchored hips.** On every peer the ragdoll's hips stay within **0.25 m** (tunable, put in `PhysicsTuning`) of the authoritative capsule position at all times. Exceeded → snap hips back (hard clamp or strong spring). Limbs may differ in detail; the *body location* may not.
- **G3 Same recovery.** Recovery is triggered only by the host's `_net_limb_end`; get-up plays on all peers; final feet position equals the authoritative final transform on all peers.
- **G4 Carried = attached everywhere.** While carried, the hips follow the carry anchor on every peer; limbs dangle. Phase changes (carried/thrown/ground) are replicated reliably and applied on all peers.
- **G5 Throws match.** Launch velocity is seeded identically on all peers; thrown ragdolls land in the same region on all peers.
- **G6 Late join.** A client joining mid-limp receives a full state packet (limp active, phase, remaining time, capsule transform, carrier id) and shows a correct ragdoll (or settled lying pose) without waiting for the next event.
- **G7 Security.** No client authority; every `any_peer` RPC validates `get_remote_sender_id()` and state; no self-RPC (`peer_id == multiplayer.get_unique_id()` → call locally); host owns every timer.
- **G8 One cleanup path.** A single function (`end_ragdoll_forced()` or equivalent) stops the simulator, restores the capsule/root, re-enables legs and input. It is called from **every** exit: recovery, disconnect (holder, held, or ragdolling player), teleport/elevator ride, run reset, host leaves, `_go_solo`. Never leaves a simulator running or a body in limp state on any peer.

## A.4 Design options (Phase-1 spike decides, I approve)

### Option A — Capsule-authoritative + local cosmetic ragdoll (default recommendation)
The host-simulated `BodyPhys` capsule remains the single source of truth. Each machine runs its own `PhysicalBoneSimulator3D` seeded from the replicated start transform, launch and **seed** (per-bone impulse variation from a `RandomNumberGenerator` seeded identically). The **hips are soft-anchored** to the capsule transform each physics tick (spring/clamp per G2). Limbs are free.
- Pros: tiny bandwidth, no new snapshot stream, reuses everything, host cost = capsule only if the host also skips its own bone sim for remote players (decide).
- Cons: limb poses can differ slightly between peers (Jolt is not guaranteed cross-machine deterministic). Acceptable only because G2/G3 pin the body location and the recovery pose.

### Option C — Host simulates bones, sends quantized poses
Host runs the full ragdoll and sends compressed bone poses (≈ 9–10 physical bones, ~10 bytes each with quantized position + smallest-three quaternion). Rough cost: 140 B × 15 Hz × 3 clients ≈ 6.3 KB/s while someone is limp. Clients apply poses with interpolation and run no bone physics.
- Pros: all peers see the same limbs. Cheaper on clients.
- Cons: more code (quantization, interpolation, late-join pose), host pays for all bones, a new packet stream to harden.

### Hybrid (fallback)
Option A, plus a single **reliable settle-pose packet** at rest and on recovery, so the final lying/get-up pose matches everywhere. Often the cheapest way to make A "look synced" in practice.

### Spike deliverable (Phase 1)
A small two-instance test scene (host + client) that knocks a player down, throws a limp player, and carries one. Measure and report in a table: hips divergence (m) over time for A, bandwidth (B/s) for C, awake rigid-body count, frame time, and how it *looks* (screenshots). **Recommend one. Stop for my decision.**

## A.5 Bone and body budget

- Target ≤ 9–10 physical bones per player (Hips, Chest, Head, Wing×2, Thigh×2, Tarsus×2). Others (Spine, Neck, Tail, Feet, Beak) are driven non-physically.
- They count against the **≤ 20 awake rigid bodies** budget (+ props). Policy required for several simultaneous ragdolls (suggested: max 2 full ragdolls; extras use capsule-only + canned flop pose). Document the rule and make it identical on every peer (decided by the host, replicated in L1).
- Sleep/settle: when the capsule settles, the simulator stops (bones freeze), and the settle pose is sent (hybrid).
- Verify Jolt behavior for chosen joint types in 4.7 in the spike (Pin, Cone, Hinge, Slider, 6DOF availability, limits, stability at the chosen masses).

## A.6 Message plan (extend, don't multiply)

| Event | RPC | Mode | Validation |
|---|---|---|---|
| Limp begin (+ seed, phase) | extend `_net_limb_begin` | any_peer, call_remote, reliable | sender ∈ {0, 1} (host only) |
| Phase change | new `_net_limb_phase(phase)` | same | host only |
| Recovery | extend `_net_limb_end` (+ final yaw/pose) | same | host only |
| Late-join limp state | extend `_full_state`-style packet, sent from the peer-connected path | authority, reliable | host only |
| Pose snapshots (Option C only) | new `_net_pose(packed)` | unreliable_ordered | host only |

Never call an RPC on yourself (host copy runs the shared body locally, as `host_knock_down` already does).

## A.7 Test matrix (all must pass, headless where possible, 2-instance playtest otherwise)

| # | Scenario | Pass condition |
|---|---|---|
| 1 | Charged punch knockdown | Victim ragdolls on host + client; hips within G2 tolerance throughout; both recover at the same host event |
| 2 | Victim is a client / victim is the host | Same result both ways |
| 3 | Throw a limp player | Same landing region on all peers; recovery correct |
| 4 | Carry a limp player, drop, throw | Attached on all peers; phase changes replicate |
| 5 | Carrier disconnects mid-carry | Ragdoll released and recovers; no stuck sim |
| 6 | Ragdolling player disconnects | Node cleaned on every peer, no orphan simulator |
| 7 | Elevator ride / teleport while limp | G8 cleanup; no limp state left; legs re-plant |
| 8 | Run reset / `_go_solo` / host leaves | Everything cleared; solo play works |
| 9 | Late join during an active ragdoll | Joiner sees correct ragdoll/lying pose (G6) |
| 10 | Double knockdown / parry-recoil knockdown / lunge-cancel | No double-start, no stuck state |
| 11 | 3–4 players limp at once | Budget policy respected; identical on all peers |
| 12 | Packet loss/lag simulation (if possible) | Hips stay anchored; recovery still lands correctly |

Add `tests/test_ragdoll_sync.tscn` modeled on `test_house_network` (host + client, scripted knockdown, asserts G2/G3/G6/G8 numerically) and wire it into `run_checks.ps1`. Existing suites stay green.

## A.8 Things that will bite (known pitfalls)

- Remote nodes: use stored references (`p.hands`, simulator refs), never `get_node_or_null` path guesses on replicated visuals.
- `class_name` order: preload new scripts where consumers are parsed first.
- Camera: the owner's camera must not live inside a tumbling head; decide the target (capsule / hips / smoothed head) and test for jitter.
- `punch_hitbox.gd` dedupes by walking to the peer-id root: bones must not be separate "players" to it. Ragdoll collision layers must not be punchable by accident or shove other capsules.
- Late replies from the host (see the parry-resurrection bug): apply stale-guard checks to every ragdoll message.

---

## A.9 NETWORKING AUTHORITY: you may improve the existing host/client calls

The current networking is a starting point, not a contract. You are allowed, and encouraged, to restructure it **where it makes the ragdoll, limp, carry or player systems more reliable, simpler or better synced**. This covers existing RPCs, signals, the `_net_*` functions in `player.gd`, `CarryRegistry`, `BodyPhys`, `GameState`, `Network`, `world.gd`.

### Recommended direction (use judgment; deviate with reasons)

1. **Replicate state, derive signals locally.** Instead of wrapping each event in its own RPC (`_rpc_hold_begin` → `hold_begin.emit`), prefer: client sends an *intent* via a validated `any_peer` RPC → host changes state → state is replicated → each peer emits its own signals from a **property setter** when the value actually changes (`if v == old: return`). `TableBase._sync` already does this; extend the pattern.
2. **Use `MultiplayerSynchronizer` for slow, discrete state** (limp state/phase, carry holder, roster, `GameState` values, table state). It handles late join automatically, so hand-built catch-up packets (`_full_state`, `_send_prop_state_to_peer`, parts of `_sync_roster`) can be removed **one at a time** once covered. Use "on change" replication for values that rarely change.
3. **Keep custom snapshots for physics.** Props, the `BodyPhys` capsule and any ragdoll pose stay on unreliable_ordered, changed-only, host-simulated, client-interpolated snapshots. Do NOT put fast-moving physics on `MultiplayerSynchronizer`.
4. **One sender-validation helper** (e.g. `_from_host()` and `_valid_sender(expected_id)`) replaces repeated inline checks. Past bugs (`teleport_to`, `_net_parry`) came from inconsistent checks.
5. **`network.gd` is the only file that knows about ENet.** Nothing else creates peers or assumes ENet, so a Steam/relay `MultiplayerPeer` can be swapped in later without touching gameplay code. Offline/solo keeps using `OfflineMultiplayerPeer`.
6. **Use `MultiplayerSpawner`** for anything that appears at runtime (hitboxes, spawned props), as already done for players.

### Rules for any networking change (guardrails)

- **The Sync Guarantees G1–G8 still apply and take priority over refactoring convenience.**
- **Verify before relying on it:** check the Godot 4.7 docs for `MultiplayerSynchronizer` / `SceneReplicationConfig` behavior (replication modes, visibility, authority, late-join). If something is unclear, build a tiny two-instance test first.
- **Migrate incrementally.** One system per slice. Never rewrite all networking in one pass. Old and new paths must not both drive the same state.
- **Tests first as the safety net:** before removing an old RPC, make sure a headless/2-instance test covers its behavior (`test_house_network`, `test_cluckjack_network`, the new `test_ragdoll_sync`). Keep all existing suites green after every slice.
- **Security stays:** host owns every timer and all authoritative state; every `any_peer` RPC validates sender + state; no self-RPC; clients never write authoritative state.
- **Stale-message guard:** state arriving late must not resurrect something already ended (see the parry-resurrection bug). Setters and handlers must be idempotent.
- **Decision gate:** present a short networking-change plan (what changes, what is deleted, what tests cover it, risks) and wait for my "go" before the first networking refactor slice. After that, proceed slice by slice.
- **Document it:** record each change and reason in `docs/PLAYER_OVERHAUL.md`, and update the RPC lists in `BUILD_GUIDE.md` / `COMBAT_MECHANICS.md`.
- **Out of scope unless I ask:** adding Steam/online relay, rollback netcode, or client-side prediction. Keep the design compatible with them, but don't build them.
- **Teaching still applies (Part B):** explain each new networking concept (setter-driven signals, synchronizer config, authority) the first time it appears, and give editor steps for any `MultiplayerSynchronizer` setup as EDITOR TASK cards, including exactly which properties to tick in the replication panel.

# PART B — TEACHING STANDARD (Godot + Blender)

## B.1 Global rules

1. **Every editor action is a numbered step.** One action per step. Never "set up the skeleton" without the clicks.
2. **Exact UI paths**, using the real labels of the **Godot 4.7 Steam** editor, e.g. `Scene dock → right-click Player → Add Child Node → type PhysicalBoneSimulator3D → Create`. If unsure of a label in 4.7, say so and give how to find it (Help → search, or hover tooltip).
3. **Each step states the expected result** ("you should now see a node named X under Y; the inspector shows Z").
4. **"If you see X instead"** line for the common failure of each tricky step.
5. **Concept box** the first time a concept appears: what it is, why we need it, one-sentence analogy. (Rest pose, bone, `BoneAttachment3D`, PhysicalBone, joint types, influence, layers/masks, etc.)
6. **Checkpoints:** after each group of ~5–8 steps, a "run this and you should see…" verification (screenshot description, or output text).
7. **Naming conventions** are given up front and reused (e.g. `Hips`, `Thigh_L`, `Tarsus_R`).
8. **Values are exact**: sizes, masses, angles, damping, joint limits, with the reason for each.
9. **Never assume I know a shortcut or menu.** If a step needs a shortcut, give both the shortcut and the menu path.
10. **Undo/rollback note** at risky steps ("if this goes wrong, Ctrl+Z, or reopen scene X").
11. **Done-when** line ends every card.
12. **Ask me to paste back** errors, Output-panel text or a screenshot description when something fails. Don't guess.
13. **Run the import step** and tell me when a new `class_name` script needs the editor to rescan.

## B.2 EDITOR TASK card template

```
### EDITOR TASK <n>: <title>
Goal: <one sentence>
Concept(s): <links to concept boxes, new ones explained below>
Time estimate: <minutes>
Before you start: <scene to open, nodes that must exist>

Steps
1. <action> — Expect: <result>
   If you see <X>: <fix>
2. ...

Values table (if any)
| Node | Property | Value | Why |

Checkpoint: <what to run/look at, what you should see>
Rollback: <how to undo>
Done when: <observable condition>
Paste back if it fails: <what to paste>
```

## B.3 SCRIPT HANDOFF card template

```
### SCRIPT HANDOFF <n>: <file path>
Attach to: <node/scene>
Needs (nodes/exports/groups): <list>
What it does: <3 lines>
How to wire it: <steps in the editor: attach script, assign exports, connect signals>
How to test: <what to run, expected output/behaviour>
```

## B.4 Preferred rigging path: NO Blender

Recommended for a blocky fowl made from primitives:
1. Build the `Skeleton3D` **inside Godot**: select the Skeleton3D node → in the Inspector open **Bones** → add bones and set parent + rest transforms (give click-by-click, including exact rest positions per bone).
2. Meshes are **rigid pieces** (CapsuleMesh / BoxMesh / SphereMesh) parented to **`BoneAttachment3D`** nodes (one per bone, with `bone_name` set). No skin weights, no weight painting, no Blender.
3. **Physical skeleton:** with the Skeleton3D selected, use the editor's **Skeleton3D → Create Physical Skeleton** action (verify the exact menu name in 4.7). It generates a `PhysicalBoneSimulator3D` with `PhysicalBone3D` nodes. Then: delete the physical bones we don't want (see budget), set each joint type/limits/mass/damping per a values table, set collision layers/masks from `physics_layers.gd`.
4. Test the simulator in a throwaway scene first (a floor, one player-less rig, a button to `physical_bones_start_simulation()`), then integrate.

Tradeoff to state honestly: rigid parts do not bend like a skinned mesh (a smoothly bending neck/wing needs skin weights, i.e. Blender or a skinned import). For a blocky/low-poly chicken this is fine.

## B.5 If Blender is truly required

Only after I approve at the decision gate. Then **BLENDER TASK cards** with the same discipline:

1. Required Blender version (name it, e.g. a current LTS) and the Godot import route (glTF 2.0, `.glb`).
2. Scene setup: units (metric, scale 1.0), **forward/up axes** that match Godot (Godot: -Z forward, +Y up; state the glTF export setting that handles this), **apply all transforms** (Ctrl+A → All Transforms) before rigging.
3. Armature: create bones step by step (Edit Mode, extrude with E), naming (same names as in Godot, `.L/.R` vs `_L/_R` pick one and stay consistent), **bone roll/orientation** and why it matters for joint axes.
4. Skinning: parenting with automatic weights, then weight painting fixes per body part; checklist to verify by posing bones.
5. Export: exact glTF export checkboxes (Include → Selected Objects; Transform; Geometry; Skinning on; Animation off unless needed), file path in `res://`.
6. Godot import: open the `.glb` → **Advanced Import Settings** → skeleton options, root type, scale, rest-pose handling (give exact fields).
7. Verification: a posed screenshot in Blender and in Godot; compare. Common failures (mesh exploded, bones rotated 90°, tiny/huge scale) with fixes.

No Blender step may say "do the usual"; every click is written out.

## B.6 Pacing

- Never dump a whole phase of editor work at once. Hand me **one card (or a short group)**, wait for my "done / here is the problem", then continue.
- Keep an `Open questions` list at the end of each message instead of burying questions in prose.
- When I say "explain more", give a deeper concept box without redoing the steps.
