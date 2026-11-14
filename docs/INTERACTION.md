# Interaction / Carry / Throw / Combat

Everything in `dev-fowl-play/interaction/` and `dev-fowl-play/player/`.

## The two contracts

### Interactable (`interaction/interactable.gd`)

Anything a player can aim at and use implements:

```
interact(player)             # run when the player presses Interact
get_interaction_prompt(player) -> String   # HUD prompt text
can_interact(player) -> bool   # range, cooldown, hand-full, etc.
```

Use `Interactable.can(node)` everywhere instead of `has_method("interact")` — it's the single contract check for focus, prompts, glow, and hands. It covers buttons, signs, terminals, physics props, and downed players.

### Carryable (`interaction/carryable.gd`)

Anything that can be picked up, carried, dropped, and thrown implements:

```
pickup(holder)               # called by Carrier when picked up
release(throw, direction, speed)  # called on drop/throw
is_carried() -> bool
get_carry_offset() -> Vector3     # item: single hand; player: both hands
get_throw_speed(charge: float) -> float
```

GDScript has no interfaces — `Carryable` documents the contract; `Carrier.pickup(target)` calls `target.pickup(owner)` if the target implements it, so items (`PhysicsProp`) and downed players share ONE code path.

## Player states (`player/player_state.gd`)

Explicit state machine with guarded transitions:

| State | Meaning |
|-------|---------|
| IDLE | free to move, punch, parry, pick up |
| CHARGING_PUNCH | Q held for charged punch |
| PARRYING | F held, parry grace window open |
| KNOCKED_DOWN | stunned, can't act, getting back up |
| CARRYING | holding an item or downed player |
| CARRIED | being carried by another player (downed) |
| THROWN | in flight after being thrown |
| RAGDOLL | tumbling physics body (downed, tumbling, carryable) |

Use `is_transition_legal(new)` before `transition_to(new)`. `can_*` queries are derived from state only; input handlers own timing details (cooldowns, spam guards, charge meters).

Key queries: `is_knocked_down()`, `is_carried()`, `is_ragdoll()`, `is_ragdolled()`, `is_carrying()`, `is_idle()`, `can_punch()`, `can_parry()`, `can_pickup()`, `can_interact()`.

## Carrier (`player/carrier.gd`)

Client-side bookkeeping + charge UI. One reference (`carried`) + charge state — no scattered `_carry_mode` / `_carried_item` / `_carried_player_id`.

- `pickup(target)` — records `carried`, calls `target.pickup(owner)` if it implements Carryable, resets charge. Returns false if already carrying.
- `start_charge()` / `release_charge()` — drive the throw-meter UI (0..1, -1 when not charging).
- `drop(threw)` — clears `carried`, emits `released(threw)`.
- `is_carrying()` / `is_carrying_player()` — the latter excludes items (checks `not (carried is PhysicsProp)`).

Replication stays with the carried object: props via `_sync_holder.rpc`, players via `_pickup_request.rpc` / `_launch_carried_player.rpc`.

## Player (`player/player.gd`)

Thin coordinator: input → component calls (Focus / Combat / Carrier / PlayerState), RPCs, node mutation. All carry/combat state lives in the components.

- `held_name()` — name of what we're carrying (via Carryable's `get_interaction_prompt`)
- `charge_meter()` — 0..1 while charging, -1 otherwise
- `is_stunned()` — knocked down / ragdolled / carried
- `get_interaction_prompt(player)` — "Pick up" if downed/knocked down, else "Interact"
- `interact(player)` — pickup request for downed/ragdolled players (host-authoritative RPC)
- `pickup(holder)` / `release(throw, direction, speed)` / `is_carried()` / `get_carry_offset()` / `get_throw_speed(charge)` — Carryable interface
- `_handle_carry_input(event)` — G drop, Q throw/charge, Q pickup
- `_apply_carry_throw(charge)` — single throw path: props go through `request_release.rpc_id(1, true)`, players go through `_launch_carried_player.rpc_id(...)`
- `take_punch(attacker_id, charge, is_charged)` — host-authoritative: parry reflect ragdolls attacker; charged punch ragdolls target (12 m/s lunge); light jab = brief flinch + jiggle recoil, no knockdown
- `apply_ragdoll(direction, speed, seconds)` — delegates to Combat
- `_ragdoll_physics(delta)` — tumbling physics, recovers when slow
- `_apply_jiggle(delta)` — visual-only mesh offset spring: recoils on impact then returns

## Combat (`player/combat.gd`)

- `LUNGE_SPEED := 12.0` — charged punch lunge speed
- `PUNCH_RANGE := 3.0` — reach limit
- `PUNCH_CHARGE_MS := 500` — hold Q this long for a charged punch
- `PARRY_COOLDOWN := 1.5`, `PARRY_GRACE := 1.5`
- `can_start_punch_charge()` — not charging, not downed, not carrying, not ragdolled
- `can_do_light_jab(now)` — 0.35s spam guard
- `raycast_hit()` — only players (identified by `has_node("Head")`, not duck-typing)
- `lunge(speed)` — launch owner forward on charged punch
- `apply_ragdoll(direction, speed, seconds)` — state transition + launch + tumbling rotation
- `start_parry(now)` / `expire_parry(now)` / `is_parrying(now)` — parry grace + cooldown
- `validate_punch(sender, target, charge)` — host-side reach/state validation

## Jiggle spring (visual-only "jelly body")

`_apply_jiggle(delta)` in `player.gd`: spring toward zero with stiffness `JIGGLE_STIFFNESS := 14.0` and damping `JIGGLE_DAMPING := 0.6`. Set `_jiggle_velocity` on impact (light jab sets `dir * 2.0`); the offset is applied to `$Body.position` each frame — visual only, no collision change. No `SoftBody3D`.

## Parry

- `hands.set_guard(true)` — both hands posed in front of the face (boxing guard); `false` relaxes to rest
- On a successful parry, the attacker is ragdolled back away from the defender (`direction = attacker - target`, speed 10.0, 2.5s)
- Parry grace: 1.5s active window while holding F; 1.5s cooldown after

## Ragdolled players

Ragdoll = CharacterBody3D stays; input locked; tumbling rotation; recovers when slow. Ragdolled players can be carried. A carried ragdolled player rides in front of the carrier (`get_carry_offset() = (0, 0.2, -1)`), head-look only (rotation locked to carrier).

## RPC flow

Host-authoritative. `get_remote_sender_id()` validates callers. Players are named by their peer ID string at spawn (`world.gd: _spawn_player` sets `p.name = str(id)`), so throw targeting uses `str(c.name).to_int()`.

- `punch_request(target_id, charge)` — client → host; host validates reach/state
- `take_punch(attacker_id, charge, is_charged)` — host → target; applies punch
- `_pickup_request(carrier_id, carried_id)` — host → all; each machine sets its own CARRYING/CARRIED state
- `_launch_carried_player(direction, speed, target_id)` — host → carried player; release with launch velocity

## Adding an interactive object in 5 lines

```gdscript
extends Interactable  # or add Interactable methods to an existing Node3D

func interact(player: Node) -> void:
    # do the thing

func get_interaction_prompt(player: Node) -> String:
    return "Do the thing"

func can_interact(player: Node) -> bool:
    return true   # add range/hand-full checks here
```

Focus, prompts, glow, and hands all route through `Interactable.can(node)` — no type-based special-casing needed.

## Adding a Carryable object

Implement the five Carryable methods on your node; `Carrier.pickup(target)` will call `target.pickup(owner)` automatically:

```gdscript
func pickup(holder: Node) -> void:
    # disable collision, snap to holder, etc.
func release(throw: bool, direction: Vector3, speed: float) -> void:
    # re-enable physics, apply launch if throw
func is_carried() -> bool:
    return holder_id != 0
func get_carry_offset() -> Vector3:
    return Vector3(0.38, -0.28, -0.85)  # item: single hand
func get_throw_speed(charge: float) -> float:
    return lerpf(3.0, 14.0, clampf(charge, 0.0, 1.0))
```

## Tests (`dev-fowl-play/tests/`)

Run `run_checks.ps1` with a Godot path:

```
pwsh dev-fowl-play/tests/run_checks.ps1 -GodotPath "C:\path\to\godot.exe"
```

Checks: import, cluckjack rules, house/hand, smoke, cluckjack network (host+client), physics network (host+client).

House test covers: carry controls, prop rooms, lore guides, collision geometry, throw speeds, pickup reach/line-of-sight, single-slot carry, charge cap, throw physics, wall-blocked pickup, drop on G, RMB tap throw, disconnect releases prop, escaped prop returns home, lore modal, Escape closes lore, **carrier disconnect**, **double-pickup rejection**, **drop-on-teleport**, **punch-while-carrying rejection**, **state-machine transitions**.
