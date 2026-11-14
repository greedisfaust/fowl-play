# PHASE_A_PLAN.md — Phase A checkpoint deliverable

Status: **awaiting your approval** (brief §9 CHECKPOINT). Nothing is edited until you say go.

This document is the Phase A (b–e) output: diagnosis, architecture, migration plan, keep/replace/delete table, Claude-vs-User split, slice order, Question Cards, and performance budget. It follows `brief PHYSICS_BRIEF.md` §9 and `CLAUDE.md` Teaching Mode.

Source of evidence: raw headless test output (Phase A step a), captured in this session:
- `test_cluckjack.tscn`: 2042 checks, 0 failures (PASS)
- `test_house.tscn`: 57 checks, 0 failures (PASS)
- smoke `--quit-after 120`: clean exit, no errors (PASS)
- `test_cluckjack_network.tscn` host + client: PASS
- `test_house_network.tscn` host + client: FAIL — `physics ENet timeout` + hundreds of `RPC '_sync_snapshot' is not allowed ... authority is 0` on `BodyPhys` nodes

Docs already exist and are reused as-is: `docs/ENVIRONMENT_MIGRATION.md` (full inventory of `house_environment.gd`, node-path contracts, cut-over checklist), `docs/ARCHITECTURE.md`, `docs/STATUS.md`.

---

## 1. Diagnosis: why in-world behavior and tests disagree

**Single-player passes, multiplayer physics fails.**

- `test_house.tscn` runs as local host (peer 1). `BodyPhys._physics_process` claims `set_multiplayer_authority(1)` when `multiplayer.is_server()` is true, so the host simulates and `_sync_snapshot` RPCs are allowed. All 57 checks pass.
- `test_house_network.tscn` runs host + client over ENet (port 17778). On the **client**, `is_authority = false`, `freeze = true`, so the client only interpolates. But `_sync_snapshot` is declared `@rpc("authority", ...)` — only the authority peer may send it. The client is rejected with `RPC '_sync_snapshot' is not allowed ... authority is 0` (repeated hundreds of times). Because no snapshots flow host→client, the client never receives transforms, the host's 20 s ENet timer fires, and both sides time out at `test_house_network.gd:148`.

**Root cause:** `autoload/body_phys.gd` does not implement the brief's authority model (§4.4: "Host simulates, clients interpolate. Send state only when changed"). The RPC mode / authority-claiming logic lets the client attempt to send snapshots it isn't authorized to send, and provides no working host→client interpolation path.

**Fix direction (confirmed by the spike requirement, brief §5):** rework `BodyPhys` replication so the host owns simulation and pushes changed-only snapshots that clients are allowed to receive; clients never fabricate position/launch. The authority-swap spike builds a two-instance (host + client) grab/throw scene and measures camera feel, transform handback, disconnect mid-carry, and teleport mid-throw before committing to the rigid-body swap vs Plan B (scripted tumble on the existing character body).

---

## 2. Architecture

### 2.1 Classes (one job per file)

| File | Extends | Role |
|---|---|---|
| `scripts/physics_tuning.gd` (+ `resources/physics_tuning.tres`) | RefCounted (+ resource) | Single tuning source; all constants with units in names (seconds, m/s, kg, Hz) |
| `interaction/interactable.gd` | Node | Component contract: USE / GRAB / BOTH; static `find()`; delegation to owner |
| `scripts/input_table.gd` | RefCounted | Pure `resolve(state, input, held_seconds) -> Action`; no node deps; headless-testable |
| `player/player_state.gd` | RefCounted | State machine: IDLE / CHARGING_PUNCH / PARRYING / LIMP / CARRYING; LIMP sub-phases GROUND/CARRIED/THROWN; transition matrix; `tick_limp_timer` |
| `player/carrier.gd` | RefCounted | Client-side carry bookkeeping + charge UI; sends `hold_request_*` to host |
| `player/combat.gd` | RefCounted | Host-authoritative punch/parry validation, reach, lunge, ragdoll launch |
| `interaction/physics_prop.gd` | BodyPhys | Carryable prop; Interactable contract; pickup/drop/throw via CarryRegistry; out-of-bounds home return |
| `autoload/body_phys.gd` | RigidBody3D | **REWORK** — physical-body base: authority, impulses, carry mode, limp mode, sleep, impact events, changed-only snapshots |
| `autoload/carry_registry.gd` | Node | Host-owned single source of truth for "who holds what"; one forced-termination path |
| `player/player.gd` | CharacterBody3D | Owns RPCs + node mutations; wires Combat/Carrier/Focus; hands.gd hooks only (out of scope) |
| `player/focus.gd` | Node | Aim, prompt, highlight (BC-12: hover/glow only on act-on-able things, healthy players never glow) |

### 2.2 Authority and RPC surface

- Host = peer 1, authoritative over all physics and carry state. Clients send intent only (press/release, aim direction, charge).
- `BodyPhys`: host simulates (`freeze = false`, claims multiplayer authority 1); clients freeze + interpolate toward changed-only host snapshots (unreliable_ordered, only when transform changes, none while sleeping or carried).
- `CarryRegistry`: host-only. `hold_request_pickup/drop/throw` are `@rpc("any_peer", "call_local")` validating `get_remote_sender_id()` + state + reach + LoS + single-slot + rate limit. Replication via `hold_begin` / `hold_end` / `hold_launch` signals → `_rpc_hold_*` (`@rpc("authority", "call_remote")`) to all peers.
- Every `any_peer` RPC validates sender and state (brief code rule). Host owns timers (limp, charged-punch auto-fire, parry cooldown).
- One forced-termination path (brief 4.4): holder/held disconnect, elevator ride, teleport, run reset, host leaves, holder becomes limp, limp recovery. A throw charge in progress at such an event ends as a drop, never a throw.

### 2.3 Carry / limp / recoil flow

**Pick up:** client aims at a prop/limp body with an `Interactable` of kind GRAB, presses E → `CarryRegistry.hold_request_pickup` → host validates reach/LoS/single-slot → `_apply_hold` sets `BodyPhys.set_carry_mode(holder, offset)` → `hold_begin` replicated to all → body follows carrier anchor with spring + wall raycast (no clipping).

**Drop / throw:** client releases Q → `hold_request_drop` (drop) or `hold_request_throw` (throw, host clamps charge to [MIN_THROW_SPEED, MAX_THROW_SPEED]) → `clear_carry_mode(launch)` → `hold_end` + optional `hold_launch` replicated.

**Limp:** charged punch hits → host calls `combat.apply_ragdoll` → `PlayerState.transition_to(LIMP)` + `BodyPhys.set_limp_mode(seconds)` → host simulates the limp body (owner authority suspended) → body is GRAB-able, carry-able, throw-able like a prop → timer expires (reset on drop, doesn't run while carried) → `limp_recovered` → `clear_limp_mode`, authority returns to owner at body's transform.

**Recoil:** thrown object or quick punch hits a body → host broadcasts a small event → each peer plays a local cosmetic jiggle/flinch → back to normal. Not limp, not an interactable. Limp wins if both apply.

---

## 2.4 Collision layer and mask table (brief 4.1 design deliverable)

One source of truth. Nothing sets layers or masks anywhere else.

| Layer | Lives on | Collides with (mask) | Rays that hit it |
|---|---|---|---|
| 1 | World static (walls, floors, roofs, elevator cab shell) | 1, 3, 5, 6 | focus ray, LoS ray |
| 2 | Devices (buttons, keys, terminals, plaques) | 5, 8 | focus ray |
| 3 | Props (loose on floor) | 1, 3, 5, 6 | focus ray, LoS ray |
| 4 | Carried objects (held by player or limp body) | — (none) | focus ray |
| 5 | Healthy players (capsule) | 1, 2, 3, 6 | focus ray, LoS ray |
| 6 | Limp bodies | 1, 3, 5 | focus ray, LoS ray |
| 7 | Elevator doors | 5, 6 | LoS ray |
| 8 | Focus / interaction ray (kinematic probe) | — | n/a (hits 2, 3, 4, 5, 6) |
| 9 | Line-of-sight ray (pickup validation) | — | n/a (hits 1, 2, 3, 5, 6, 7) |

Rays are configured per-query via `collide_with` mask, not by living on a layer. Carried objects (layer 4) collide with nothing so they can't jam against walls while carried; the carry spring raycast stops them at surfaces.

Implementation: a constants file (or a single `PhysicsLayers` autoload/resource) holds these values; every `CollisionShape3D` layer/mask is set from it in the editor or in `_ready`. This is the example used to teach layers and masks (brief 4.1).

---

## 3. Environment migration plan and room-scene layout

**Rule (brief §3.5 / §3.6):** cut over one room at a time; the game launches at every step; no script re-spawns the world at runtime. Hand-placed props are scene instances (identical on every peer by construction). Small `@tool` editor helpers (auto-collision, scene validation) are welcome.

**Room scenes (OPEN — recommend):**
- `rooms/apartment.tscn` → instanced into `world.tscn` as `Apartment` (x = 0)
- `rooms/casino.tscn` → `Casino` (x = 100)
- `rooms/rest.tscn` → `Rest` (x = 50)

**Node-path contracts (kept unchanged — from `ENVIRONMENT_MIGRATION.md`):**
`Apartment`, `Casino`, `Rest`; `Apartment/Elevator`, `Rest/Elevator`, `Casino/Elevator`; `Apartment/NicknameTerminal`, `JoinTerminal`, `LobbyConsole`, `ColorBoard`, `PlayerBoard`; `Rest/StatusBoard`; `Spawn` markers (in each room); `Casino/ChickenCross`, `Casino/Cluckjack`; `Players`; `MultiplayerSpawner` (spawn path `../Players`); `HUD`; `WorldEnvironment`; `DirectionalLight3D`; `House` node (removed only when `house_environment.gd` is deleted).

**Kit first (brief 3.4):** before dressing rooms, build a small kit with the user: a wall / window / shell scene set and a prop palette. Hand-placing 100+ objects one at a time is too slow.

**Inventory:** `docs/ENVIRONMENT_MIGRATION.md` already records every text, number, color, shader line, prop, plaque, light, and furniture piece from `house_environment.gd` (all seven lore plaques with full text, floor shader to extract to `res://shaders/floor.glshader`, Kenney GLB asset list). Use it as the cut-over checklist per room:
1. Build `rooms/<name>.tscn` from the inventory (shell, floor, lights, furniture, props, plaques, text).
2. Instance into `world.tscn` at the contract name/path.
3. Verify against the doc (every prop name/position/pickup, plaque title+short+body, light position/color/energy/range, text string).
4. Remove that room's section from `house_environment.gd`.
5. Run `run_checks.ps1`; fix regressions.
6. Commit.

When all three rooms are cut over: delete `house_environment.gd`, its `.uid`, and the `House` node; grep for stragglers (brief 3.6).

---

## 4. Keep / fix / replace table (evidence per row)

| File | Verdict | Evidence |
|---|---|---|
| `scripts/physics_tuning.gd` | KEEP | Single tuning source; units in names; used by BodyPhys, physics_prop, carrier, combat, input_table. Matches brief 4.5 / 6.1. (TODO to migrate consts into `resources/physics_tuning.tres` — leave for now due to headless bootstrap timing.) |
| `resources/physics_tuning.tres` | KEEP | Exists; verify code reads one consistent source, no duplication. |
| `interaction/interactable.gd` | KEEP | Single component contract (USE/GRAB/BOTH), static `find()`, delegation. Matches brief 4.4 / 6.2 BC-12. Used by physics_prop + tests. |
| `scripts/input_table.gd` | KEEP | Pure `resolve(state, input, held_seconds)`; no node deps. Exactly the testable function brief 6.1 requires. Matches Q/E/F/LMB input table. |
| `player/player_state.gd` | KEEP | State machine + transition matrix + LIMP sub-phases + `tick_limp_timer`. Matches brief 4.2 / 6.2. |
| `player/carrier.gd` | KEEP | One carry path; client bookkeeping + charge UI; sends `hold_request_*` to host. Matches brief 4.4 / 6.2 BC-8 / BC-9. |
| `player/combat.gd` | KEEP | Host-authoritative punch validation, parry, reach, lunge, ragdoll launch. Matches brief 4.3 / 6.2 BC-3 / BC-4 / BC-6. |
| `interaction/physics_prop.gd` | KEEP | Extends BodyPhys; Interactable contract; pickup/drop/throw via CarryRegistry; out-of-bounds home return. Matches brief 4.4 / 4.5 / 6.2 BC-15 / BC-17. |
| `autoload/body_phys.gd` | REWORK | Broken at baseline (authority/RPC mismatch causes house network test failure). Must match brief §4.4 authority model. Authority-swap spike decides mechanism. |
| `autoload/carry_registry.gd` | FIX | Works for single-slot carry/throw/disconnect cleanup; needs review for limp-player carries and full forced-termination matrix (every holdable × every exit path). |
| `player/player.gd` | INSPECT | Not yet read — orchestrates Combat/Carrier/Focus, input, RPCs. Verify InputMap actions only (no raw keycodes), hands.gd hooks only. |
| `player/focus.gd` | INSPECT | Not yet read — aim/prompt/highlight; needed for BC-12. |
| `environment/house_environment.gd` | REPLACE | Retired per brief §3 / §12; delete after room-by-room migration. |
| `player/hands.gd` | OUT OF SCOPE | Hooks only; never change its look or revert the user's edits (CLAUDE.md out of scope). |

---

## 5. "Claude does / User does" split (with difficulties)

| # | Task | Who | Difficulty | New concept taught |
|---|---|---|---|---|
| 1 | Authority-swap spike scene (host + client grab/throw) | User builds from my EDITOR TASK cards; I write the spike logic | medium | authority, multiplayer authority, host vs client simulation |
| 2 | Rework `BodyPhys` replication (host sim, clients interpolate, changed-only snapshots) | Claude | — | — |
| 3 | Fix `CarryRegistry` for limp-player carries + forced-termination matrix | Claude | — | — |
| 4 | Add `PhysicsLayers` constants / layer-mask table applied to all collision shapes | Claude + User (apply in editor) | easy | collision layers & masks |
| 5 | Prop palette kit (wall/window/shell scenes + prop palette) | User builds from my EDITOR TASK cards | medium | scenes over script-built hierarchy, StaticBody |
| 6 | First prop end to end (inherit base Prop scene, mesh, profile) | User builds from my EDITOR TASK cards; I write profile/tuning | easy | PropProfile, Interactable GRAB, group `physics_props` |
| 7 | First device on interaction model (behavior unchanged) | User builds; I wire Interactable | easy | Interactable USE, prompts, glow |
| 8 | First room cut over (suggest Apartment) | User builds the room scene; I remove script section | medium | room scene, node-path contract |
| 9 | Rest room cut over (repeat mode) | User builds; I remove script section | easy | repeat mode |
| 10 | Casino room cut over (repeat mode) | User builds; I remove script section | easy | repeat mode |
| 11 | Limp player Tier 1 (host-simulated rigid body, placeholder shape) | User builds placeholder; I write limp logic | hard | limp = ragdoll = ONE concept, authority suspension |
| 12 | Combat reactions (recoil, parry, auto-firing charged punch w/ re-arm + cooldown) | Claude + User playtest | hard | pure input table, charged-punch state |
| 13 | Cleanup matrix (every forced termination × every holdable) | Claude + User playtest | medium | forced termination, one code path |
| 14 | Delete `house_environment.gd` + `.uid` + `House` node; grep stragglers | Claude | easy | — |
| 15 | Tier 2 skeletal ragdoll | PENDING rigged model + user training (not time-blocked) | hard | PhysicalBoneSimulator3D / PhysicalBone3D |

Teaching budget (brief 2.4): teach in full for foundation, first prop, first device, and the Apartment; repeat mode for Rest and Casino.

---

## 6. Slice order with a playtest after each (brief 9.C)

1. Inventory + node-path contracts — `docs/ENVIRONMENT_MIGRATION.md` already complete; verify against `world.gd` and tests.
2. Foundation + one loose prop end to end — tuning, profile, body, registry, interactable, pure input table, host sim, client interpolation. **Teach in full.**
3. Devices on the interaction model — behavior unchanged. **Teach in full for the first device.**
4. Kit, then first room cut over — suggest the Apartment. **Teach in full.**
5. Limp player Tier 1.
6. Combat reactions — recoil, parry, auto-firing charged punch with re-arm and cooldown.
7. Cleanup matrix — every forced termination against every holdable thing.
8. Remaining rooms (Rest, then Casino) in repeat mode, then delete `house_environment.gd`.
9. Tier 2 skeletal ragdoll — pending rigged model + user training; not time-blocked.

Each slice: build → run tests + launch smoke check → PLAYTEST request → fix → update `docs/BUILD_GUIDE.md` → commit.

---

## 7. Question Cards (OPEN items — need your answers)

**Q1 (OPEN-1, blocks Tier 2):** Where does the rigged player model come from? (Asset, creation, or placeholder plan needed before Tier 2 skeletal ragdoll can be scoped.)

**Q2 (brief 4.3 OPEN):** Impact-speed threshold for thrown-object recoil? Does a thrown limp player hitting a healthy player cause recoil? Does recoil interrupt a wind-up?

**Q3 (brief 6.1 OPEN):** Movement during charged-punch wind-up — full speed, slowed, or rooted? Can F (parry) be pressed during jab recovery?

**Q4 (brief 6.3 OPEN — decide in plan):**
- A bettor goes limp mid-hand at Cluckjack or Chicken Cross: auto-stand, auto-cash-out, or the hand waits? (Cluckjack already auto-stands when the bettor disconnects.)
- Does a carried or limp player count as "aboard" for the elevator button? What happens to a limp player during the ride?
- Does the 5% shakedown (BC-7) apply to the shared wallet or a per-player share, and how does it appear in the day report?
- Can a limp player be carried onto a table's buttons or into the elevator doorway without jamming?

**Q5 (performance budget):** Confirm the target — 4 players on weak school laptops. Proposed caps: awake rigid bodies ≤ 20, sleep threshold default, max 4 shadow-casting lights. Confirm or adjust.

**Q6 (room layout):** Confirm the recommended room scenes (`rooms/apartment.tscn`, `rooms/casino.tscn`, `rooms/rest.tscn`) instanced into `world.tscn` as `Apartment`/`Casino`/`Rest` at x = 0/100/50.

---

## 8. Performance budget (brief 3.8)

Target: 4 players on weak school laptops.

- Prefer mesh + `StaticBody3D` (or baked CSG) for walls over live CSG with collision.
- Cap on awake rigid bodies: **≤ 20** (props + limp bodies combined).
- Sleep thresholds: bodies sleeping when below threshold; snapshots stop while sleeping or carried (already in BodyPhys).
- Limit shadow-casting lights: **≤ 4** omni lights; rest are baked or non-shadow.
- Hand-placed props are scene instances (identical on every peer) — no runtime spawning except the single networked spawn function.

---

## Next step

Please review the plan above and answer the Question Cards (Q1–Q6). Once approved, I'll proceed to Phase B.5 (authority-swap spike) and then Phase C slice 1, following Teaching Mode with EDITOR TASK cards and SCRIPT HANDOFF CARDS for everything you build in the editor.

**Nothing is edited until you approve the plan.**
