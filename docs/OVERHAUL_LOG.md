# OVERHAUL LOG — Fowl Play foundation refactor

**Branch:** `features/physics-overhaul-and-mechanics` (PR target: `main`)
**Commit baseline:** `15e56f4` + uncommitted work (carrier.gd, hands.gd, player.gd, player_state.gd, test_house.gd, world.gd, docs/INTERACTION.md)
**Phase:** 0 — Understand (read-only; no code changed in this phase)
**Status:** CHECKPOINT — awaiting review before Phase 1

This log is the single source of truth for the overhaul. It is written before any code changes so the design, not a patch, drives the work. Sections:

1. System map (current)
2. Contradiction ledger (each contradiction → where it lives → how the new design removes it)
3. Proposed architecture (components, owners, authority, RPC surface)
4. Migration table (file → keep / merge / delete / new)
5. Risks and decisions that need your review

---

## 1. System map (current)

Verified by reading every file listed; nothing below is assumed.

### Terminology decision (applied to this log)
**knockdown = ragdoll = "limp" = ONE concept.** A limp player:
- has no control (movement and actions locked) but is still a real physical body in the world;
- is an interactable (`kind = GRAB`) that can be aimed at and picked up like any carryable;
- while carried, hangs/follows the carrier with weight and swing/lag (not rigidly glued);
- can be dropped (flops to ground) or thrown (tumbles through air, can slam into walls);
- recovers (stands up, regains control) only when NOT carried and its timer/settle condition is met.

A limp player is "a prop that happens to be a person" — carrying and throwing it uses the exact same carry and physical-body path as a prop.

### Core loop / autoloads
- `autoload/network.gd` — ENetMultiplayerPeer UDP 7777, host = peer 1, clients = peers 2–4, roster/nick/color, `State { SOLO, HOSTING, JOINING, JOINED }`.
- `autoload/game_state.gd` — wallet, quota, day, timer, phase (REST/DAY), extra life, ledger, `run_reset` signal. Host-authoritative money (`try_spend`, `add_money`, `_set_wallet.rpc`).
- `autoload/style.gd` — shared font + text scale.

### Player system (`dev-fowl-play/player/`)
- **player.gd** — `CharacterBody3D`, thin coordinator. Input → Focus / Combat / Carrier / PlayerState, RPCs, node mutation. Holds `state`, `focus`, `combat`, `carrier`, `_highlight` components plus legacy vars (`_charge_started`, `_knocked_down_until`, `_carrier_id`, `_carried_player_id`, `_pickup_attempting`, `_just_picked_up`, `input_locked`). Implements Carryable methods (`pickup`/`release`/`is_carried`/`get_carry_offset`/`get_throw_speed`) for when this player IS carried. RPCs: `punch_request`, `take_punch`, `_net_jab`, `_net_punch`, `_net_state`, `_net_hover_state`, `_net_hover_point`, `_net_reach`, `_launch_carried_player`, `_wall_hit_vfx`, `teleport_to`.
- **player_state.gd** (`class_name PlayerState`) — state machine `IDLE, CHARGING_PUNCH, PARRYING, KNOCKED_DOWN, CARRYING, CARRIED, THROWN, RAGDOLL` with `is_transition_legal` / `transition_to`. Holds `ragdolled_until`. Queries `can_punch`, `can_parry`, `can_pickup`, `can_interact`, `is_knocked_down`, `is_carried`, `is_ragdoll`, `is_ragdolled`, `is_carrying`, `is_idle`, `is_thrown`. **To be redesigned: merge KNOCKED_DOWN + RAGDOLL into LIMP; CARRIED + THROWN become LIMP sub-phases.**
- **carrier.gd** (`class_name Carrier`) — client-side bookkeeping + charge UI: `carried: Variant`, `charge_started`, `charge_held`, `owner`. `pickup`/`drop`/`start_charge`/`release_charge`. Never calls RPCs itself.
- **combat.gd** (`class_name Combat`) — punch/parry/knockdown/ragdoll logic, host-authoritative. `validate_punch`, `apply_ragdoll`, `lunge`, `start_parry/expire_parry/is_parrying`, `can_start_punch_charge`, `can_do_light_jab`, `raycast_hit`.
- **focus.gd** (`class_name Focus`) — local focus/hover/glow/prompt. `update(ray, player, input_locked, mouse_captured, carrier, held_name)` each frame. Uses `Interactable.can()`; walks raycast colliders up to a node whose name matches `^\d+$` or that implements the contract; suppresses hover on healthy (non-stunned) players.
- **hands.gd** (`class_name Hands`) — procedural first-person + world hand models. Public API: `set_hover`, `update_hover_point`, `reach`, `set_color`, `add_sway`, `set_speed`, `set_guard`, `shake`. DO NOT change how hands look or revert uncommitted work (R7).

### Interaction contracts (`dev-fowl-play/interaction/`)
- **interactable.gd** (`class_name Interactable extends Node3D`) — contract `interact(player)`, `get_interaction_prompt(player)`, `can_interact(player)`, static `can(node)` checks `has_method("interact")` + `has_method("get_interaction_prompt")`. NOTE: nothing actually extends `Interactable`; `PhysicsProp`, `PressButton`, `TextTerminal`, `LorePlaque` all implement the methods by duck-typing on their own node types (RigidBody3D / StaticBody3D).
- **carryable.gd** (`class_name Carryable extends RefCounted`) — contract `pickup(holder)`, `release(throw, direction, speed)`, `is_carried()`, `get_carry_offset()`, `get_throw_speed(charge)`. Document-only; GDScript has no interfaces.
- **physics_prop.gd** (`class_name PhysicsProp extends RigidBody3D`) — host-simulated prop. RPCs `request_use`, `request_push`, `request_charge`, `request_release`, `_sync_holder`, `_sync_motion`, `_notice`. `REACH=3.2`, `CHARGE_SECONDS=1.25`, `MIN_THROW_SPEED=3.0`, `MAX_THROW_SPEED=14.0`, `linear_damp=0.8`, `angular_damp=1.5`. 15 Hz transform snapshots forever. `held_by(tree, who)` scans `physics_props` group.
- **lore_plaque.gd** (`class_name LorePlaque extends StaticBody3D`) — `interact` → `player.read_lore(title, body)`; `get_interaction_prompt` → "Read <title>".
- **focus_highlight.gd** — `material_overlay` glow on hovered target; `set_target`/`clear`.

### Other interactable consumers
- `tables/press_button.gd` (`PressButton extends StaticBody3D`) — `interact` emits `pressed(value)`; `get_interaction_prompt` → label text. Used by elevator GO button and bet-panel keys.
- `lobby/text_terminal.gd` (`TextTerminal extends StaticBody3D`) — `interact` locks player input + typing UI; `get_interaction_prompt` → "Edit <title>".
- `tables/bet_panel.gd` — builds PressButton keys; `key_pressed` signal consumed by table scripts.

### World / environment
- **world.gd** — `Node3D` in `game_world` group. Player spawning (`_spawn_player` sets `p.name = str(id)`), elevator `_ride`/`_send_all_to` (calls `player.teleport_to.rpc_id` and `prop.drop_for_transition(id)`), `_settle_tables`, `_day_report`, dev teleport K/L. `_on_peer_disconnected` (uncommitted) releases carried player on carrier disconnect + clears `_carrier_id`.
- **environment/house_environment.gd** — `_apartment`/`_casino`/`_rest` layout; `_prop`/`_furniture`/`_asset` builders duplicate collision + model placement; mixes shells, furniture, notices, props, lore in one ~380-line file. Prop names `Prop%02d` by child index (deterministic per-peer since build order is fixed).

### Tables / UI / elevator (out of scope except where they call new APIs)
- `tables/table_base.gd`, `tables/cluckjack/`, `tables/chicken_cross/` — economy, rounds, bets (guardrail: do not change rules/numbers).
- `ui/interaction_overlay.gd` — HUD prompt/inventory/charge meter; reads from focus + carrier.
- `elevator/elevator.gd` — doors, ride-request button, aboard tracking.

---

## 2. Contradiction ledger

Each entry: what contradicts what, where it lives, and how the new design removes it.

| # | Contradiction | Where it lives | How the new design removes it |
|---|---|---|---|
| C1 | `Interactable` is a `class_name Node3D` contract but nothing extends it; it is only a duck-typed convention (`has_method("interact")`). `PhysicsProp` (RigidBody3D), `PressButton`/`TextTerminal`/`LorePlaque` (StaticBody3D) cannot share a base class (GDScript single inheritance). Prompt/highlight logic still type-branches in places. | `interactable.gd:1-2`; `physics_prop.gd`, `press_button.gd`, `text_terminal.gd`, `lore_plaque.gd` | R1: `Interactable` becomes a **component `Node`** (child of the interactable object, not a base class) with `kind` (USE/GRAB/BOTH), `enabled`, `can_interact`, `interact`, `get_interaction_prompt`, `interacted` signal, plus static `find(collider)` that walks up to locate the component. Focus/overlay/hands use `Interactable.find()` — one lookup, one prompt source, one highlight rule, no type chains. |
| C2 | Two parallel carry implementations: items use PhysicsProp RPCs (`request_use`/`request_charge`/`request_release`/`_sync_holder`); downed players use Player RPCs (`_pickup_request`/`_launch_carried_player`) + Carryable methods. `Carrier.pickup()` calls `target.pickup(owner)` if it exists, but replication stays split. | `physics_prop.gd`, `player.gd` (carry/throw RPCs), `carrier.gd` | R2: **one holder↔held relationship**, host-authoritative, one pickup/drop/throw path for items and players. A host-side **CarryRegistry** (autoload) owns "who holds what"; both `PhysicsProp` and `Player` register releases through it. |
| C3 | Player state spread across `PlayerState`, `Carrier`, `Combat`, legacy vars in `player.gd` (`_charge_started`, `_knocked_down_until`, `_carrier_id`, `_carried_player_id`, `_pickup_attempting`, `_just_picked_up`), plus `input_locked` hacks and `ragdolled_until` duplicated between `player_state.gd` and `player.gd`. | `player.gd:716-724`, `player_state.gd`, `carrier.gd`, `combat.gd` | R4: `PlayerState` is the single answer to "what can this player do?". Fold `ragdolled_until`, `_launch_until`, `input_locked` into states/state data. **Delete legacy compat vars** in `player.gd`; update tests. Input/interact/punch/pickup/movement-lock/hover/hands all query `PlayerState`. |
| C4 | One input action (`punch_charge`) means both "charge a punch" and "charge a throw". E and left mouse both run the same interact path, so a cup beside a keypad is picked up when you meant to press a button. | `player.gd:_handle_carry_input` / `:_combat_input`; `InputMap` | R6: separate actions USE, GRAB, DROP, THROW (charge), PUNCH, PARRY. Context resolution (what a press does given state + target) lives in **one place** (the input handler / interaction model). Produce a final input table for review. |
| C5 | Held items found by scanning the `physics_props` group every call (`PhysicsProp.held_by`). Players found by walking raycasts up to a node whose name matches `^\d+$`. | `physics_prop.gd:held_by()`; `player.gd:_peer_of_node()` / `:_try_interact()`; `combat.gd:raycast_hit()` | R1/R2: CarryRegistry is the single source of truth for "who holds what"; player lookup uses deterministic spawn paths (`Players/<peerId>`) rather than name matching. |
| C6 | Escape while charging a throw **drops the item** instead of cancelling the charge. A lost mouse-release (cursor released, input locked, typing at a terminal) leaves the host still charging, so the next tap becomes a full-power throw. Client charge clock vs host-decided power. | `player.gd:_cancel_charge()` → `carrier.drop(false)`; `carrier.gd:charge_started` (client) vs `physics_prop.gd:_charge_started` (host) | R2: host times the charge; cancelling a charge **never** drops; client sends aim with release and host validates/clamps; host resets charge state on every exit path (drop, throw, teleport, knockdown, disconnect, elevator, reset). |
| C7 | Throw direction/origin come from the host's interpolated copy of the thrower's head; client sends no aim with release. Client throws can leave off-aim. | `player.gd:_apply_carry_throw()` (direction local only; `request_release.rpc_id(1, true)` sends no direction/speed) | R2/R8: client sends aim direction with release RPC; host validates reach/state, clamps speed, applies launch. |
| C8 | Sender never sees their own punch swing (`_net_jab`/`_net_punch` are `call_remote`). | `player.gd:448-454` | R8: local swing plays on the sender's own machine (call_local or direct local call). |
| C3 | Player state spread across `PlayerState`, `Carrier`, `Combat`, legacy vars in `player.gd` (`_charge_started`, `_knocked_down_until`, `_carrier_id`, `_carried_player_id`, `_pickup_attempting`, `_just_picked_up`), plus `input_locked` hacks and `ragdolled_until` duplicated between `player_state.gd` and `player.gd`. Also `KNOCKED_DOWN` and `RAGDOLL` are separate states when they should be ONE `LIMP` state. | `player.gd:716-724`, `player_state.gd`, `carrier.gd`, `combat.gd` | R4: `PlayerState` is the single answer to "what can this player do?". Merge `KNOCKED_DOWN` + `RAGDOLL` into `LIMP`; `CARRIED` and `THROWN` become LIMP sub-phases. Fold `ragdolled_until`, `_launch_until`, `input_locked` into per-state data. **Delete legacy compat vars** in `player.gd`; update tests. |
| C4 | One input action (`punch_charge`) means both "charge a punch" and "charge a throw". E and left mouse both run the same interact path, so a cup beside a keypad is picked up when you meant to press a button. | `player.gd:_handle_carry_input` / `:_combat_input`; `InputMap` | R6: separate actions USE, GRAB, DROP, THROW (charge), PUNCH, PARRY. Context resolution (what a press does given state + target) lives in **one place** (the input handler / interaction model). Produce a final input table for review. |
| C9 | Physics feel: `linear_damp = 0.8` makes props floaty; player gravity 20 vs prop default 9.8; no `PhysicsMaterial`; throws set velocity in the same frame the body is unfrozen. | `physics_prop.gd:_ready()`, `player.gd:GRAVITY=20.0` | R3: **BodyPhys** — one centralized physical-body class for props AND limp players. All tuning constants (damping, gravity scale, friction, bounce, throw speeds, limp mass/inertia/swing-lag) in ONE place. No separate prop-physics vs player-physics code. |
| C10 | Every prop sends a 15 Hz transform snapshot forever, even when asleep / carried. | `physics_prop.gd:_physics_process()` (`_sync_motion.rpc` every 1/15 s unconditionally) | R3/R8: BodyPhys replicates only-changed snapshots; stops while sleeping or carried; resumes on wake. Applies to props AND limp bodies. |
| C11 | Pickup reach validated against the host's lagged copy of the client's position (clients stream `_net_state` at ~15 Hz unreliable). | `physics_prop.gd:_can_reach()` uses `player.head.global_position` | R8: host validates against its own authoritative snapshot; note residual latency as known limitation (movement not yet host-authoritative — see guardrail). |

**Defects verified against live code:**
- D1 Carrier disconnect leaves carried player stuck — PARTIALLY fixed in uncommitted `world.gd:_on_peer_disconnected`, but still uses legacy `p._carrier_id = 0` and ad-hoc release. Not covered for: carrier knocked down, host leaves, carried disconnects cleanly in all paths.
- D2 Throw/RPC targeting uses `str(c.name).to_int()` (peer ID name) — works but fragile; ties targeting to node naming.
- D3 `input_locked` zeroes launch velocity on frame 1 (`player.gd:_physics_process` line ~653) — an ad-hoc hack to be folded into state.
- D4 `teleport_to` drops carried items (bug #11 fix present) but does not reset charge state.
- D5 `_net_hover_state` / `_net_reach` RPCs fire every frame on change; no rate limiting.

---

## 3. Proposed architecture

**Principles:** host-authoritative; one contract per concern; no abstraction without ≥2 real consumers today (R9); static typing, no `:=` (R9); `##` header on every script (R9); one responsibility per script, `player.gd` stays thin (R9).

### Components & owners

```
Interaction component (Interactable, Node child of interactable object)
  ├ kind: USE | GRAB | BOTH
  ├ enabled: bool
  ├ can_interact(player) -> bool
  ├ interact(player)
  ├ get_interaction_prompt(player) -> String
  ├ signal interacted(player)
  └ static find(collider) -> Interactable   # walks up to find component

CarryRegistry (autoload, host-owned)
  ├ holder_id -> held_id, held_id -> holder_id   # single source of truth
  ├ request_pickup(holder_id, held_id) -> bool   # host validates reach/LoS/single-slot
  ├ request_drop(holder_id, threw)
  ├ request_throw(holder_id, direction, charge)  # host times charge, clamps speed
  ├ on_holder_disconnect(id), on_held_disconnect(id)
  ├ on_teleport(id), on_elevator_transition(id), on_run_reset(), on_host_leave()
  └ cleanup guaranteed: disconnect × either party, reset, elevator, teleport,
      knockdown end, carrier knocked down, host leaves

### BodyPhys (centralized physical-body class — ONE class for everything)
**New class.** Props AND limp players share one physical-body foundation:
  - one authority model (host simulates, clients interpolate only-changed snapshots);
  - `apply_impulse`, `apply_launch(direction, speed)`, `set_carry_mode(holder, offset)`, `set_limp_mode()`;
  - impact event → wall-slam VFX hook (scaled by speed);
  - sleep / wake (replication on/off; stop snapshots while sleeping or carried);
  - ALL tuning constants in ONE place: damping, gravity scale, friction, bounce, MIN/MAX throw speed, CHARGE_SECONDS, REACH, limp mass/inertia/swing-lag;
  - replication: snapshot only when changed; stop while sleeping/carried; resume on wake.
  `PhysicsProp` and the limp-player body both use `BodyPhys` (or a thin wrapper). No separate prop-physics vs player-physics code.

PlayerState (single state machine; R4)
  states: IDLE, CHARGING_PUNCH, PARRYING, LIMP, CARRYING
  LIMP has sub-phases: LIMP_GROUND (lying), LIMP_CARRIED (being hauled), LIMP_THROWN (airborne)
  CARRIED and THROWN are NOT separate top-level states — they are phases of LIMP.
  legal-transition matrix documented; state_entered_at; per-state movement_locked /
  input_locked data (replaces input_locked hacks); limp timer lives here only.
  All input/interact/punch/pickup/hover/hands query it.

Carrier (client bookkeeping + charge UI; unchanged shape, R7)
  carried reference + charge state; never calls RPCs.

Focus / FocusHighlight / Hands / Overlay
  route through Interactable.find() + PlayerState queries; hands look/API untouched (R7).
```

### Authority model (DECISION MADE — from user, implemented per this log)

**Principle: limp = host-simulated physical body.** While limp, the owner's movement authority is suspended and the body is driven by the host exactly like a prop, so a client can never fabricate a launch or position.

- **Loose prop:** host simulates (`multiplayer.is_server()`), clients freeze + interpolate BodyPhys snapshots only while awake. (Existing, keep.)
- **Limp player (ground / carried / thrown):** host simulates the BodyPhys body. Owner's camera stays attached to their body so they see themselves lying on the ground, being dragged, or flying.
- **Carried:** the carrier's aim (look direction) and movement drive the anchor point. The limp body follows it with a spring (weight + slight swing). Host-validated, same carry path as items.
- **Recovery:** when limp ends, authority returns to the owner at the body's current transform, with a clean resync (no snap through walls). Host transitions LIMP → IDLE, owner regains control.
- **Cleanup:** carrier disconnects, owner disconnects, reset, elevator, teleport: always release and resolve to a sane state (see cleanup matrix).

Implementation detail left to the coder; the principle is fixed.

### RPC surface (consolidate, R8)

Current (scattered): `punch_request`, `take_punch`, `_net_jab`, `_net_punch`, `_net_state`, `_net_hover_state`, `_net_hover_point`, `_net_reach`, `_launch_carried_player`, `_wall_hit_vfx`, `teleport_to`, prop `request_use`, `request_push`, `request_charge`, `request_release`, `_sync_holder`, `_sync_motion`, `_notice`, `_pickup_request`.

Target (fewer, consistent naming, explicit modes, all `any_peer` RPCs validate `get_remote_sender_id()` + phase/state; basic rate limiting on new RPCs):

- `punch_request(target_id, charge)` — client → host (unchanged, validated)
- `take_punch(attacker_id, charge, is_charged)` — host → target (unchanged)
- `carry_pickup(holder_id, held_id)` — host → all (replaces `_pickup_request`)
- `carry_launch(direction, speed, target_id)` — host → carried (replaces `_launch_carried_player`)
- `carry_release(holder_id, threw)` — host → all (holder drops; replaces per-prop `_sync_holder(0)` and player `release`)
- `prop_motion(pos, rot)` — host → clients, only when changed / not sleeping (replaces per-prop 15 Hz `_sync_motion`)
- `net_state(pos, yaw, pitch)` — owner → host, 15 Hz unreliable (movement; existing)
- `net_hover(on, point)`, `net_reach(point)` — owner → others (existing; rate-limit)
- `wall_hit_vfx(speed)` — any peer (existing)
- `teleport_to(pos, yaw)` — host-only (existing)

Late-join behavior: state explicitly documented — join-in-progress is unsupported (GameState `_full_state` lacks phase/ledger); a joining peer spawns at lobby and waits for the next elevator. No change in this overhaul (guardrail: out of scope).

---

## 4. Migration table

| File | Action | Reason |
|---|---|---|
| `interaction/interactable.gd` | Merge/rewrite | Node3D → component `Node`; add `kind`, `enabled`, static `find(collider)`; keep `interacted` signal |
| `interaction/carryable.gd` | Keep | Documents the Carryable contract; may become a mixin-like helper if ≥2 consumers |
| `interaction/physics_prop.gd` | Merge / thin wrapper | Use BodyPhys for simulation + replication; remove per-prop 15 Hz snapshot; route hold state through CarryRegistry; remove `held_by()` scan |
| `new: autoload/body_phys.gd` | New | Centralized physical-body class for props AND limp bodies: authority, impulses, launch, carry mode, sleep/wake, changed-only replication, ALL tuning constants in one place |
| `new: autoload/carry_registry.gd` | New | Host-owned registry owning "who holds what"; one pickup/drop/throw path for props and limp players; guaranteed cleanup on disconnect/reset/elevator/teleport/knockdown/host-leave |
| `interaction/lore_plaque.gd` | Keep + add Interactable component | Lore plaque gets an Interactable child component (kind=USE) |
| `tables/press_button.gd` | Keep + add Interactable component | Button gets an Interactable child component (kind=USE) |
| `lobby/text_terminal.gd` | Keep + add Interactable component | Terminal gets an Interactable child component (kind=USE) |
| `tables/bet_panel.gd` | Keep + add Interactable component | Each key gets an Interactable child component (kind=USE) |
| `elevator/elevator.gd` | Keep + add Interactable component | GO button gets an Interactable child component (kind=USE) |
| `player/player_state.gd` | Merge | Redesign: states `IDLE, CHARGING_PUNCH, PARRYING, LIMP, CARRYING`; LIMP sub-phases `LIMP_GROUND / LIMP_CARRIED / LIMP_THROWN`; merge KNOCKED_DOWN + RAGDOLL into LIMP; fold `ragdolled_until` + `input_locked` hacks into per-state data; document transition matrix |
| `player/carrier.gd` | Keep | Client bookkeeping + charge UI; never calls RPCs (unchanged) |
| `player/combat.gd` | Keep | Punch/parry/knockdown/ragdoll logic; host-authoritative (unchanged shape) |
| `player/focus.gd` | Merge | Use `Interactable.find()` instead of `Interactable.can()` + name-walking; remove healthy-player suppression hack if component `kind` handles it |
| `player/hands.gd` | Keep (hooks only) | Add "holding an item" / "grab-hover vs point-hover" hooks if needed; do NOT change look or public API (R7) |
| `player/player.gd` | Merge | Thin coordinator; delete legacy compat vars (`_charge_started`, `_knocked_down_until`, `_carrier_id`, `_carried_player_id`, `_pickup_attempting`, `_just_picked_up`); consolidate input into separate actions; limp body uses BodyPhys |
| `environment/house_environment.gd` | Split/merge | `_prop`/`_furniture`/`_asset` → one prop template/factory (R5); file shrinks to layout + declarations |
| `world.gd` | Merge | `_send_all_to` uses carry registry for prop drops + player teleport; `_on_peer_disconnected` uses registry cleanup (no ad-hoc `_carrier_id`) |
| `tests/test_house.gd` | Rewrite | Port every legacy-API check to new API; add R10 checks |
| `docs/OVERHAUL_LOG.md` | New | This file |
| `docs/INTERACTION.md` | Rewrite | Finalize contracts, authority table, transition matrix, RPC surface, input table, "add in under 10 lines" example |
| `README.md`, `docs/ARCHITECTURE.md`, `docs/STATUS.md`, `docs/HOUSE_AND_HAND.md`, `docs/ROADMAP.md` | Update where behavior changed | Guardrail: update docs with actual behavior |

**Delete (nothing with consumers left):**
- `PhysicsProp.held_by()` static scan → replaced by CarryRegistry
- Player root lookup by `^\d+$` name-walking → replaced by deterministic `Players/<id>` paths
- Legacy compat vars in `player.gd` → replaced by PlayerState
- `input_locked` hacks → replaced by per-state movement/input lock data
- Per-prop 15 Hz unconditional snapshot → replaced by changed-only replication

---

## 5. Risks and decisions that need your review

These are the places where I should NOT proceed unilaterally:

1. **knockdown = ragdoll = "limp" = ONE concept.** `KNOCKED_DOWN` and `RAGDOLL` merge into `LIMP`; `CARRIED` and `THROWN` become LIMP sub-phases (`LIMP_CARRIED`, `LIMP_THROWN`). This changes the PlayerState transition matrix and every consumer that checks `is_knocked_down()` / `is_ragdolled()` / `is_ragdoll()`. Confirm this is the intended model — the rest of the architecture (carry path, BodyPhys) is built on it.

2. **BodyPhys centralization (R3).** ONE physical-body class for props AND limp bodies. Confirm props should lose their custom `linear_damp=0.8` / default gravity in favor of shared BodyPhys tuning, and that limp players use the same BodyPhys as props (not a separate CharacterBody3D ragdoll path).

3. **Input map (R6).** Final split of USE / GRAB / DROP / THROW (charge) / PUNCH / PARRY, default bindings, and context-resolution rule (e.g., "GRAB when looking at a carryable, USE otherwise"; "THROW charge only while carrying"). Keep defaults as close to current as makes sense. **Flagged as a design decision to review; update README + docs.**

4. **Interactable component vs. base class (R1).** I'm planning `Interactable` as a component child `Node` with static `find(collider)`. Confirm acceptable, or argue for keeping `class_name Interactable extends Node3D` with duck-typing.

5. **CarryRegistry scope (R2).** Host-owned autoload owning "who holds what". Confirm it should cover both props and limp players, and that cleanup runs on: carrier disconnect, carried disconnect, run reset, elevator transition, teleport, knockdown ending, carrier knocked down, host leaves.

6. **Behavior re-tunes to report (section 7 of the prompt):** Any deliberate change from current behavior must be called out. Known candidates: Escape no longer drops while charging (cancels charge instead); throw direction comes from client aim (host-validated) instead of host's interpolated head; props stop snapshotting while asleep/carried. Confirm these are acceptable or adjust.

7. **`docs/INTERACTION.md` vs. `docs/OVERHAUL_LOG.md`.** The untracked `docs/INTERACTION.md` already describes the current contracts. It must be rewritten *with* the code, not after. Confirm it stays the "source of truth" for the two contracts as they evolve.

8. **Tests cannot run here.** Godot 4.7 console is not installed on this machine. Every code change is **unverified** until you run:
   `./dev-fowl-play/tests/run_checks.ps1 -GodotPath '<path to Godot_v4.7.1 console exe>'`
   (PowerShell) or the Bash equivalent from this repo root.

---

**End of Phase 0.** No file has been modified except `docs/OVERHAUL_LOG.md` (created). Please review sections 2–5, approve or adjust the architecture and decisions, then I'll proceed to Phase 1 (commit the current uncommitted baseline) and Phase 2 (build the foundation).
