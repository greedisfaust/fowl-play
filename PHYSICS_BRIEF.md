# PHYSICS_BRIEF.md: Scene-built world + centralized physics

Labels: **DECIDED** (do not relitigate), **OPEN** (ask with a recommendation), **OUT OF SCOPE** (do not touch).
Standing rules, Teaching Mode and card formats live in `CLAUDE.md`. They apply to everything below.

## 1. Mission
`environment/house_environment.gd` builds the whole world from script on every peer. The editor view is not what runs, and physics and interaction were bolted on per object. That is the root of the bugs.

**DECIDED**
1. `house_environment.gd` is retired and finally deleted. The user builds the environment by hand in the editor, following your step-by-step instructions. No script generates rooms, furniture or props at runtime.
2. You build the reusable foundation every physical thing plugs into (props, furniture, limp players) and write all the logic scripts, each with a SCRIPT HANDOFF CARD.
3. Work is back and forth and **teaching-first**: the user creates things only as you tell them exactly what and where, and learns the pattern as they go.
4. The project must benefit: at the end, the user and teammates can add a prop, a device and a room from `docs/BUILD_GUIDE.md` without asking anyone.

**Prior work is not trusted by default.** A previous session committed a partial foundation (BodyPhys, CarryRegistry, Interactable, PlayerState, Carrier/Combat/Focus) and its last pass created new bugs. Phase A must decide keep, fix or replace for each piece from evidence (section 9). Any script may be overhauled or deleted.

## 2. Cut line and priorities
There is no hard deadline. Priorities, in order:
- **Must ship:** Phase A, B and B.5; slices 1 to 5 (foundation, devices, Apartment cut over, limp Tier 1 working for host and client); the cleanup matrix.
- **Should ship:** combat reactions, Rest and Casino cut over, `house_environment.gd` deleted, `docs/BUILD_GUIDE.md` complete.
- **Pending:** Tier 2 skeletal ragdoll — blocked on having a rigged player model and on teaching the user how to set up `PhysicalBoneSimulator3D` / `PhysicalBone3D` per bone. Not time-blocked; asset- and training-blocked. Ship Tier 1 first.
- **Acceptable fallback:** props and Tier 1 limp done; Casino still on the old script behind a clearly marked legacy path, with `docs/ENVIRONMENT_MIGRATION.md` listing what remains.
- **Plan B for limp physics:** if the authority-swap spike fails, use a scripted tumble on the existing character body (no rigid-body swap).
- **Teaching budget:** teach in full for the foundation, first prop, first device and the Apartment; use repeat mode afterwards.

## 3. Retiring `house_environment.gd`
Room-by-room strangler migration. The game launches at every step.
1. **Inventory (read-only).** Write `docs/ENVIRONMENT_MIGRATION.md` listing everything the script produces per room (Apartment, Casino, Rest, sky): shells, floors, walls, roofs, window frames/panes, trim, lift openings, city silhouettes; the floor shader (extract to `.gdshader`), sky/environment, ambient light, every light (position, color, energy, range); furniture (Kenney GLBs with scale, position, collision footprint); every prop (name, position, size, color/asset, pickup yes/no) and procedural cup/chip/carton models; every sign and `Label3D`; **all seven lore plaques with full text**; table dressing, coffee machines, rugs, damage marks and other storytelling. Copy all text, numbers, colors and shader code into the doc or extracted assets **before** removing anything.
2. **Node-path contracts.** Keep these paths or update code and tests together: `Apartment`, `Casino`, `Rest` (at x = 0, 100, 50), `Apartment/Elevator`, `Rest/Elevator`, `Casino/Elevator`, `Apartment/NicknameTerminal`, `JoinTerminal`, `LobbyConsole`, `ColorBoard`, `PlayerBoard`, `Rest/StatusBoard`, the `Spawn` markers, `Casino/ChickenCross`, `Casino/Cluckjack`, `Players`, `MultiplayerSpawner` (spawn path `../Players`), `HUD`, `WorldEnvironment`, `DirectionalLight3D`, and the `House` node. Verify against `world.gd` and the tests.
3. **Room scenes. OPEN (recommend):** `rooms/apartment.tscn`, `rooms/casino.tscn`, `rooms/rest.tscn`, instanced into `world.tscn` with the names above. Independent editing, testing and merging.
4. **Kit first.** Before dressing rooms, build a small kit with the user: a wall / window / shell scene set and a prop palette they can paint rooms with. Hand-placing 100+ objects one by one is too slow.
5. **Cut over one room at a time:** EDITOR TASK cards to build it, the user places and dresses it, you remove that room's section from the script and run the checks. Props in a finished room are hand-placed scene instances (identical on every peer by construction).
6. **Delete** the script, its `.uid`, the `House` node and every reference when no room uses it. Grep for stragglers.

**DECIDED:** no replacement script that re-spawns the world at runtime. Small `@tool` editor helpers (auto-collision, scene validation) are welcome.

**Performance:** target 4 players on weak school laptops. Prefer mesh + StaticBody (or baked CSG) for walls over live CSG with collision. Set a cap on awake rigid bodies, sleep thresholds, and a limit on shadow-casting lights. Report the budget in the plan.

## 4. The physics foundation
```
DATA      PhysicsTuning.tres (numbers, timings) + PropProfile.tres (per-prop class) + shared PhysicsMaterial
BODY      one physical-body base (RigidBody3D): host simulates, clients interpolate, modes, impulses, sleep, impact events
RULES     host-side registry: who holds what, validation, ONE forced-termination path
INTERACT  Interactable component (USE / GRAB) + player Focus (aim, prompt, highlight)
SPAWN     base Prop scene (+ inherited variants) and ONE networked spawn function for runtime props
```
- Static devices (buttons, keys, terminals, plaques, elevator button) use the `Interactable` component only. Simulated things (props, pushable furniture, limp players) add the physical body. Never turn devices into rigid bodies.
- Everything simulated gets pickup, carry, throw, prompts, replication, return-home out of bounds, reset and cleanup for free.
- No per-prop magic numbers. A `PropProfile` picks weight class (light/medium/heavy/immovable), pickup allowed, throwable, friction/bounce preset, size class, optional impact sound.
- New props: auto-generate collision from the mesh with an editor helper, manual override allowed.
- Special behaviors (breakable, consumable, bouncy) are optional components, never forks of the base.
- Runtime-spawned props go through the single spawn function registered with the `MultiplayerSpawner`, with deterministic names and host authority.
- **Late join:** hand-placed physics props must still send their current state to a joining peer.
- **Prop lint test:** scans every prop scene, fails if a component or profile is missing, runs spawn, grab, throw, cleanup on each. A bare RigidBody3D outside the base scene is not networked or carryable; say so in the docs.
- **Adding a prop must be:** inherit the base Prop scene, assign a mesh, pick a profile. This is the first thing taught in full, and goes into `docs/BUILD_GUIDE.md` as "add a prop in 5 steps".

### 4.1 Collision layer and mask table (design deliverable in the plan)
One table, kept in one resource or constants file, covering at least: world static, devices, props, carried objects, healthy players, limp bodies, elevator doors, the focus/interaction ray, line-of-sight rays. State for each: which layer it lives on, what it collides with, what rays hit it. Nothing sets layers or masks anywhere else. Teach layers and masks with this table as the example.

### 4.2 Limp players (knockdown = ragdoll = ONE concept)
A limp player is incapacitated and ragdolled with no control of itself. It is an interactable (GRAB), can be carried around while the carrier looks up, down, left and right (the body follows the carrier's aim with weight and swing), dropped, or thrown (tumbling, wall slams). Feel reference: the limp bodies in Gamble With Your Friends (copy nothing).
- **Authority:** the host simulates a limp body exactly like a prop. The owner's movement authority is suspended while limp, the owner's camera stays attached to their body, and authority returns at the body's transform on recovery. Clients never fabricate a launch or position.
- **Mechanism (OPEN, justify or improve):** the character body is disabled and a physical body from the same base as props takes over at that position; control swaps back on recovery. Carry, throw, replication and cleanup are then the same code as for a prop.
- **Tier 1 (first):** one host-simulated rigid body on the foundation (placeholder shape is fine).
- **Tier 2 (pending rigged model + user training):** a `Skeleton3D` with `PhysicalBoneSimulator3D` and `PhysicalBone3D` per bone. While limp the bones are the real bodies; carry and throw act on the ragdoll (spring/joint on a grab bone), the capsule only follows the root. Replicate only the root transform, changed-only; limb poses are cosmetic. Blocked until a rigged model exists and the user is taught how to build it.
- **OPEN-1 (blocks Tier 2):** where does the rigged model come from?
- **Timer rule (DECIDED):** the limp timer resets every time the body is dropped and does not run while carried. A player can be kept limp by being carried repeatedly. This is intentional (gambling is the main game). Recovery happens when not carried and the timer is up.

### 4.3 Recoil vs limp
- A quick punch or a thrown physics object hitting a body makes it **recoil**: a cosmetic jiggle/flinch, then back to normal. Recoil is not limp, not an interactable, does not incapacitate. The host decides a hit happened and broadcasts a small event; each peer plays the jiggle locally.
- A charged punch puts the target limp. A body is in recoil or limp, never both; limp wins.
- **OPEN:** impact-speed threshold for thrown-object recoil; whether a thrown limp player hitting a healthy player causes recoil; whether recoil interrupts a wind-up.

### 4.4 Carry, cleanup, replication
- One host-authoritative holder-to-held relationship for items and limp players. The client sends intent (aim direction and charge); the host validates reach, line of sight, state and single slot, clamps throw speed and applies it. No cancel of a throw charge.
- **Forced termination** always resolves through ONE code path: holder or held disconnects, elevator ride, teleport, run reset, host leaves, holder becomes limp or is knocked down, limp recovery. Nothing stays held, stuck, frozen or half-state. A throw charge in progress at such an event ends as a drop, never a throw.
- Host simulates, clients interpolate. Send state only when changed (nothing for sleeping bodies). Node names and paths are identical on every peer. Every `any_peer` RPC validates sender and state, with basic rate limiting. The host owns the clock for timed actions.

### 4.5 Tuning in one place
All numbers in one resource, with units in names. Starting values, to tune with the user. The tap window must be configurable (an accessibility toggle is planned in the GDD).

| Constant | Start | Note |
|---|---|---|
| `TAP_MAX_SECONDS` | 0.25 | a press released within this is a tap (configurable) |
| `CHARGED_PUNCH_HOLD_SECONDS` | 1.0 (decided) | held this long = charged punch auto-fires |
| `CHARGED_PUNCH_COOLDOWN_SECONDS` | 2.0 | before another can start |
| `JAB_COOLDOWN_SECONDS` | 0.35 | spam guard |
| `THROW_FULL_CHARGE_SECONDS` | 1.25 | |
| `MIN_THROW_SPEED` / `MAX_THROW_SPEED` | 3.0 / 14.0 m/s | |
| `PARRY_GRACE_SECONDS` / `PARRY_COOLDOWN_SECONDS` | 1.5 / 1.5 | |
| `LIMP_SECONDS` | 2.5 | |
| `PUNCH_RANGE` / `LUNGE_SPEED` | 3.0 / 12.0 | |

## 5. Authority-swap spike (before committing to the limp mechanism)
A throwaway scene, two instances (host + client), one player grabbing and throwing the other. The user builds it from your EDITOR TASK cards. Answer, with evidence:
1. How does the thrown player's own camera feel when the host simulates their body over LAN (round-trip delay, stutter, nausea)?
2. Does the authority handback at the body's transform work cleanly?
3. What happens with late or lost packets, a disconnect mid-carry, and a teleport mid-throw?

Report the result and choose between the rigid-body swap and Plan B. Delete the spike afterwards.

## 6. Input, combat and behavior contract

### 6.1 Input table (DECIDED; right click and old G drop are removed entirely)
Q is one key whose meaning depends on state.

| Input | Idle, not holding | Holding item or limp player | In charged-punch state | Limp |
|---|---|---|---|---|
| **Left click** | press device | blocked | blocked | blocked |
| **E** | press device, or grab a carryable/limp player (by aim) | blocked | blocked | blocked |
| **Q tap** (< `TAP_MAX_SECONDS`) | quick punch (jab) | drop | n/a | blocked |
| **Q hold** | wind-up, **auto-fires charged punch at 1.0 s** even if still held | throw charge; release = throw | n/a | blocked |
| **F** | parry (both hands to the face) | blocked | blocked | blocked |

- The charged punch fires once per press; Q must be released to re-arm and the cooldown must pass. The host enforces both. No charge meter UI for the punch (remove any); use wind-up pose and sound. The throw charge meter stays.
- In charged-punch state (wind-up, lunge, recovery) use, grab and parry are blocked; becoming limp ends it immediately.
- Release between the tap window and 1.0 s: the wind-up fizzles with short recovery (default; OPEN-confirm).
- Holding: tap drops; a longer hold commits to a throw and release always throws (min power just past the tap window, max at full charge). No cancel.
- **OPEN:** movement during wind-up (full, slowed, rooted); whether F can be pressed during jab recovery.

### 6.2 Combat mechanics (punch / parry / limp) — DECIDED

**Charge Punch (Hold Q)**
- Press Q: `combat.set_punch_charge_held(true, now)` starts charge timer; `_punch_input_active = true`, `_punch_charge_auto_fired = false`.
- Hold Q: timer accumulates. In `player.gd:_process()`, if `_punch_input_active && !_punch_charge_auto_fired && now - started >= PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS` (1.0s): auto-fire charged punch once, set `_punch_charge_auto_fired = true`.
- Release Q before 1.0s: if held ≥ 150ms → charged punch with charge = held_ms/1000ms (clamped 0..1). If held < 150ms → light jab (jiggle only, **no limp state**).
- Can't punch while: carrying anything, limp, or `carrier.is_carrying()`.

**Charged Punch — Lunge + Camera Arc**
- Charge ≥ 1.0: `combat.start_lunge(direction, LUNGE_SPEED_MPS, 0.5)` stores launch velocity with 0.5s expiry. Direction is `-camera.global_basis.z`.
- `_physics_process()` preserves lunge velocity while `combat.is_lunging(now)`; input can't overwrite x/z.
- Camera arc: `combat.steer_lunge(-(camera.global_basis.z), 1.0, 10.0, delta)` pulls lunge velocity toward camera look, capped at `max_turn_rad_per_sec` rad/s, scaled by `strength * delta`.
- Range: `PUNCH_RANGE_M = 3.0` — `combat.validate_punch()` rejects targets farther than 3m.

**Parry (F)**
- Press F: `combat.start_parry(now)` sets `_parry_active_until = now + PARRY_GRACE_SECONDS` (1.5s). `hands.set_guard(true)` tweens both hands (0.3s in) into boxer-guard pose in front of face.
- Hold F: guard stays active until `_parry_active_until` expires or F released.
- Release F: `hands.set_guard(false)` tweens both hands back (0.6s out).
- After grace expires: `_parry_cooldown = PARRY_COOLDOWN_SECONDS` (1.5s) before F can parry again.
- Can't parry while: limp, carrying, or during cooldown.
- Parry success: attacker is knocked down instead (limp + launch via `parry_riposte`).

**Guard visual**: `hands.set_guard()` uses per-hand `_guard_offset_goal[i]` / `_guard_offset_cur[i]` arrays (one per hand, index 0 = left, 1 = right) so both hands move independently to their side of the face and relax back together — no left-hand-only glitch. Hand rotations tween directly via `create_tween()` on `quaternion`.

**Limp (knockdown / carried / thrown)**
- States: `LIMP_GROUND` → `LIMP_CARRIED` → `LIMP_THROWN` → recovery to `IDLE`.
- Duration: `PhysicsTuning.LIMP_SECONDS = 2.5` for charged punch and parry-riposte; 0.35s for jab-set limp on BodyPhys.
- Jab: BodyPhys `set_limp_mode(0.35)` on target (host applies), jiggle visual on target, no player-state LIMP transition.
- Authority: host simulates limp body via `BodyPhys.set_limp_mode()` + `apply_launch()`. Clients freeze + interpolate snapshots. Client never fabricates a launch.
- Recovery: `BodyPhys.limp_recovered` signal → `_on_limp_recovered()` → `clear_limp_mode()` → `transition_to(IDLE)`.

### 6.3 RPC flow (host-authoritative)
```
Client (press Q)   → combat.set_punch_charge_held(true, now)   [local only]
Client (release Q) → punch_request.rpc_id(1, target_peer, charge) → host
Host (punch_request) → validate_punch(reach/state) → if valid:
  - Host applies limp mode + launch to target's BodyPhys directly
  - take_punch.rpc_id(target_id, sender, charge, is_charged) → target client
Target client (take_punch) → state machine + visuals only (limp, jiggle, notice)
```
`punch_request` accepts sender -1 (host local call) or peer 1 (host); rejects everything else. `take_punch` and `parry_riposte` reject any sender that isn't host (peer 1) or server.

### 6.4 Files
- `res://player/player.gd` — `_combat_input`, `_combat_do_light_jab`, `_combat_throw_charged_punch`, `punch_request`, `take_punch`, `parry_riposte`, auto-fire in `_process`, lunge velocity preservation + steer in `_physics_process`
- `res://player/combat.gd` — `start_lunge`, `is_lunging`, `lunge_velocity`, `steer_lunge`, `apply_ragdoll` (state+visuals only), parry state
- `res://player/hands.gd` — `set_guard()` (boxer-guard visual; per-hand offsets), `reach()` (poke), hover/aim math
- `res://player/player_state.gd` — LIMP state machine, transitions, limp_timer
- `res://autoload/body_phys.gd` — `set_limp_mode`, `clear_limp_mode`, `apply_launch`, `limp_recovered` signal
- `res://scripts/physics_tuning.gd` — all timing/speed constants with units in names

### 6.5 Playtest checklist
- [ ] Tap Q (fast release <150ms) → jab, target jiggles, no limp, recovers instantly
- [ ] Hold Q ≥ 1s → charged punch auto-fires while still holding
- [ ] Hold Q, look left/right during lunge → punch arcs toward camera look
- [ ] Hold F → hands come up in boxer guard, "PARRY READY" notice
- [ ] F parry + get punched → attacker knocked down instead, "PARRIED!" notice
- [ ] Charged punch hit → target goes limp for 2.5s, head slumps, frozen input
- [ ] Jab hit → target jiggles, brief input unlock, recovers instantly

**Testability requirement (DECIDED):** implement the table as a pure function `resolve(state, input) -> action`, and the state machine's transition table as data (no node dependencies). BC-1 to BC-8 become headless unit tests, including every illegal transition. Real key events stay a playtest item.

## 7. Debug overlay (DECIDED, small)
A toggleable overlay (single InputMap action) showing for each body in range: state, holder, authority peer, last impulse, awake/sleeping. Debug builds only. It makes playtest reports precise.

## 8. Tests
- **Environment tests must be rewritten.** `test_house.gd` asserts things the old script created (roofs collide, panes block, lift openings clear, at least 18 props, exactly 7 plaques, table positions, scripted prop names). Port them to **invariants against the real scenes**: every room closed by a roof, lift openings clear, every prop built from the base scene and in the group, plaque count read from the scene, nothing outside world bounds. Never delete a check without porting it.
- Add: the pure input/state tests, the prop lint test, forced termination for every holdable thing, carrier disconnect while carrying a player, double pickup, drop on teleport, throw targeting the right peer, punch while picking up, late-join prop state.
- Multiplayer: the user runs two instances (host, then join `127.0.0.1`).

## 9. Workflow
- **Phase A, Understand (read-only), in this order:**
  1. **Test-run proof.** Run the full suite on the user's machine and show the raw output. If you cannot run Godot from your shell, say so and ask the user to run it and paste the result. Nothing else is trusted until this works.
  2. Launch the game for a baseline.
  3. Trace props, devices, carry/throw, limp, and exactly what `house_environment.gd` builds.
  4. **Keep / fix / replace table** for every existing foundation file (`BodyPhys`, `CarryRegistry`, `Interactable`, `PlayerState`, `Carrier`, `Combat`, `Focus`, `PhysicsProp`, and so on), with evidence per row.
- **Phase B, Plan (no edits), deliver:** (1) diagnosis; (2) architecture (ASCII scene trees, classes, authority, RPC surface, carry/limp/recoil flow, layer table); (3) environment migration plan and room-scene layout; (4) the keep / replace / delete table; (5) the **"Claude does / User does" table**, where every user task has a difficulty (easy, medium, hard) and the new concept it teaches, so the user can choose; (6) slice order with a playtest after each; (7) every Question Card; (8) performance budget.
- **CHECKPOINT:** wait for the user's answers and approval.
- **Phase B.5, Spike:** the authority-swap spike (section 5). Report and decide.
- **Phase C slices:**
  1. Inventory + node-path contracts (`docs/ENVIRONMENT_MIGRATION.md`).
  2. Foundation + one loose prop end to end (tuning, profile, body, registry, interactable, pure input table, host sim, client interpolation). **Teach in full.**
  3. Devices on the interaction model (behavior unchanged). **Teach in full for the first device.**
  4. Kit, then the first room cut over (suggest the Apartment). **Teach in full.**
  5. Limp player Tier 1.
  6. Combat reactions (recoil, parry, auto-firing charged punch with re-arm and cooldown).
  7. Cleanup matrix (every forced termination against every holdable thing).
  8. Remaining rooms (Rest, then Casino) in repeat mode, then delete `house_environment.gd`.
  9. Tier 2 skeletal ragdoll (pending rigged model + user training; not time-blocked).
- Each slice: build, run tests and a launch smoke check, PLAYTEST request, fix, update `docs/BUILD_GUIDE.md`, commit.
- **Phase D, Delete and unify:** remove superseded mechanisms, legacy shims, old G/right-click inputs, any punch-charge UI and `house_environment.gd`. Grep every old API name.
- **Phase E, Verify and document:** full suite; update `docs/INTERACTION.md`, `OVERHAUL_LOG.md`, `ARCHITECTURE.md`, `STATUS.md`, `HOUSE_AND_HAND.md`, `ASSETS.md`, `GLOSSARY.md` and the README controls table. **Log every GDD deviation** (the earlier gun/stun plan is replaced by punch and limp).

## 10. Glossary
| Term | Meaning |
|---|---|
| Limp (= knockdown = ragdoll) | Player incapacitated by a charged punch; ragdolled body; GRAB-able, carryable, throwable. |
| Recoil | Temporary cosmetic flinch from a quick punch or thrown object; not limp, not an interactable. |
| Grab / carry / hold | Grab = pick up; carry/hold = the ongoing holder-to-held relationship. |
| Interactable | Anything the player can aim at and act on. Verbs: USE (devices) and GRAB (carryables, limp players). |
| Device | Button, keypad key, terminal key, plaque, elevator button, bet-panel key. |
| Forced termination | Ending a charge/hold by an event (disconnect, elevator, teleport, reset, host leaves, limp), not by the player. |

## 11. Out of scope
Economy and quota numbers, table rules, the day report, lobby logic, assets and licenses (except the rig question), the visual model of the hands, any new gameplay beyond this document.

## 12. Definition of done
- `house_environment.gd` is deleted; the world exists as scenes the user built in the editor, with every text, light, prop and plaque migrated or deliberately dropped (recorded in `docs/ENVIRONMENT_MIGRATION.md`).
- Props, furniture and limp players run on one physical foundation with one carry path, one cleanup path and one tuning resource.
- A new prop is: inherit the base scene, assign a mesh, pick a profile. The prop lint test passes for every prop scene.
- Limp players are grabbable, carryable, throwable and correct for host and clients (Tier 2 pending a rigged model and user training).
- The input table lives in one place as a pure function; G and right click are gone; no punch charge UI.
- Every behavior in 6.2 has a test or a recorded playtest result; the full suite passes with output shown; the user has playtested host and client.
- `docs/BUILD_GUIDE.md` lets a teammate add a prop, a device and a room without asking anyone.
- Docs describe what actually exists.
