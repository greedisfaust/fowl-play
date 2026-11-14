# BUILD_GUIDE.md — how to add stuff to Fowl Play

Teaching-mode reference for teammates and future-you. Every slice ends with updating this file (CLAUDE.md rule 10). The patterns here match the code as it stands after Phase B.5: host-authoritative ENet (port 7777, host = peer 1, up to 3 clients), CarryRegistry single source of truth, BodyPhys carry/limp/simulation foundation, and the Q/E/MOUSE1 input table.

## Conventions used here

- `res://` paths are Godot project paths. Type everything in GDScript (typed, no `:=` where the 4.7 compiler errors).
- Never read raw keycodes in gameplay code — use InputMap actions.
- Every `any_peer` RPC validates `get_remote_sender_id()` and state.
- The host owns timers; clients report press and release only.
- Money changes only through `GameState` (`_set_wallet.rpc()` on the host).

---

## Add a prop

A prop is a `PhysicsProp` (extends `BodyPhys`) with a `PropProfile` resource, an `Interactable` of kind GRAB (pickup-able) or USE (push-only), and membership in the `physics_props` group.

1. **Create the profile.** `res://resources/profiles/<name>.tres` of type `PropProfile`. Set `weight_class` (LIGHT/MEDIUM/HEAVY/IMMOVABLE), `pickup_allowed`, `throwable`, `friction`, `bounce`, `size_class` ("small"/"medium"/"large").
2. **Create the prop scene.** New Scene > Root node: `PhysicsProp` (script `res://interaction/physics_prop.gd`). Name it e.g. `PropCup`. Add a `CollisionShape3D` child with a box/capsule shape sized to the prop. In the Inspector:
   - `item_name`: display name, e.g. "Last clean cup"
   - `can_pick_up`: true for carryable, false for push-only
   - `profile`: drag in the `.tres` from step 1
   - Collision layer/mask from `PhysicsLayers` (see table below) — layer 3 (`LAYER_PROPS`), mask = WORLD_STATIC | PROPS | HEALTHY_PLAYERS | LIMP_BODIES
3. **Register the prop.** In `_ready`, `physics_prop.gd` already adds itself to group `physics_props` and builds its `Interactable`. Nothing else to wire.
4. **Place it.** Instance the prop scene into a room scene (`rooms/apartment.tscn` etc.) at the exact position from `docs/ENVIRONMENT_MIGRATION.md`. Props are hand-placed scene instances — no runtime spawning except via `CarryRegistry`.

**Success:** prop sits on the floor, focus highlight appears when aimed at, E picks it up (single hand / right hand offset), Q-tap drops it, Q-hold release throws it (host clamps to 14.0 m/s max).

---

## Add a device

A device is anything you USE rather than carry: buttons, keys, terminals, plaques. It uses the `Interactable` contract (kind `USE`) and lives on collision layer 2 (`LAYER_DEVICES`).

1. **Create the device scene.** Root node: `StaticBody3D` (or `Area3D` for triggers). Add `CollisionShape3D` sized to the device. Layer 2 (`LAYER_DEVICES`), mask = WORLD_STATIC | HEALTHY_PLAYERS | LIMP_BODIES.
2. **Add the Interactable component.** Add a child script/node of type `Interactable` (`res://interaction/interactable.gd`), kind `USE`. `Interactable.find(node)` lets other code locate it.
3. **Wire the action.** In the device script, implement `interact(player)` and `get_interaction_prompt(player)`. Connect input: `InputMap` action "use" (left click / E per `input_table.gd`) → device's `interact()` via the player's focus ray.
4. **Place it.** Instance into the room at the contract path from `ENVIRONMENT_MIGRATION.md` (e.g. `Apartment/NicknameTerminal`, `Rest/StatusBoard`).

**Success:** aiming at the device shows the prompt + glow; pressing E (USE) runs `interact()` on the host only. Left click (primary) also presses USE-kind devices when idle and not carrying; left click on a GRAB target (prop / limp player) does nothing — grab stays E-only per the DECIDED input table.

---

## Charge punch (combat)

**Input**: `InputMap` action `punch` (KEY_Q).

| Phase | Trigger | What happens |
|---|---|---|
| Press | Q pressed down | `combat.set_punch_charge_held(true, now)` starts the charge timer |
| Hold | Q held | Timer accumulates; the charged punch **auto-fires** after `PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS` (1.0s) while still holding Q. `_punch_charge_auto_fired` guards against firing twice per press. |
| Release | Q let go before 1s | Held ≥ 150ms → charged punch with charge = held_ms / 1000ms (clamped 0..1). Held < 150ms → light jab (jiggle only, **no limp** — a jab shouldn't ragdoll). |

**Can't punch while**: carrying anything, limp, or `carrier.is_carrying()` (`combat.can_start_punch_charge()` guards all of these).

**Lunge**: when charge ≥ 1.0, `combat.start_lunge(direction, LUNGE_SPEED_MPS, 0.5)` stores a launch velocity with a 0.5s expiry. Direction is `-camera.global_basis.z` (forward from where the player is looking). `player.gd:_physics_process()` reads `combat.is_lunging(now)` and sets `velocity.x/z` from `combat.lunge_velocity()` instead of move input while true.

**Camera arc (steer)**: while lunging, `combat.steer_lunge(-(camera.global_basis.z), 0.0, 3.0)` pulls the lunge velocity toward wherever the camera looks, capped at `max_turn_rad_per_sec = 3.0` rad/s — lets the player arc the punch left/right mid-lunge by looking that way.

**Range**: `PUNCH_RANGE_M = 3.0` — `combat.validate_punch()` rejects targets farther than 3m.

**Moving hitbox**: the charged-punch hitbox is parented to the puncher (`combat.spawn_punch_hitbox()`), so it moves with the puncher during the lunge instead of sitting stationary at the spawn point. Its lifetime is the full lunge duration (0.5s), so it can connect at any point during flight.

**Hit during lunge stops the lunge**: if the moving hitbox overlaps a player while the puncher is still lunging, the lunge stops immediately (`combat.finish_lunge()` sets `_lunge_until = 0` and `_lunge_velocity = ZERO`) and the hit applies — knockdown + limp for 3.5s. The puncher's own machine stops locally; remote punches get `_net_lunge_stop.rpc_id(peer_id)`. The puncher stops where they landed the punch rather than carrying through to the end of the lunge.

**Lunge ends with nothing hit**: if the 0.5s lunge expires without the hitbox overlapping anything, nothing happens — no damage, no limp, no jiggle. Normal movement input resumes after `_lunge_until` expires.

**Interrupted by another charged punch**: if the puncher is hit by another charged punch while lunging, `combat.cancel_lunge()` aborts the lunge with no hit.

**Files**:
- `res://player/player.gd` — `_combat_input`, `_combat_do_light_jab`, `_combat_throw_charged_punch`, `punch_request`, `take_punch`, auto-fire in `_process`, lunge velocity preservation in `_physics_process`
- `res://player/combat.gd` — `start_lunge`, `is_lunging`, `lunge_velocity`, `steer_lunge`, `finish_lunge`, `cancel_lunge`, parry state
- `res://player/punch_hitbox.gd` — the moving hitbox; stops the lunge on hit
- `res://scripts/physics_tuning.gd` — `LUNGE_SPEED_MPS`, `CHARGED_PUNCH_HOLD_SECONDS`, `CHARGED_PUNCH_RANGE_M`, `CHARGED_PUNCH_RAGDOLL_SECONDS`, `CHARGED_PUNCH_PUSH_SPEED_MPS`

**Success:** hold Q ≥ 1s → charged punch fires; during lunge, looking left/right arcs the punch; hitting a player mid-lunge stops the lunge at the hit point and knocks them down for ~2.5–3.5s; letting Q go early (<1s, ≥150ms) throws a partial charged punch; tapping Q (<150ms) jabs with jiggle only.

---

## Collision layers & masks (single source of truth: `res://scripts/physics_layers.gd`)

| Layer | Bit | Lives on | Mask (hits) |
|---|---|---|---|
| WORLD_STATIC | 1 | walls, floors, roofs, elevator shell | 1,3,5,6 |
| DEVICES | 2 | buttons, keys, terminals, plaques | 5,8 |
| PROPS | 4 | loose props | 1,3,5,6 |
| CARRIED | 8 | carried props/bodies | (none) |
| HEALTHY_PLAYERS | 16 | player capsules | 1,2,3,6 |
| LIMP_BODIES | 32 | incapacitated bodies | 1,3,5 |
| ELEVATOR | 64 | elevator door panels | 5,6 |

Ray masks: `MASK_FOCUS_RAY` = DEVICES | PROPS | LIMP_BODIES; `MASK_LOS_RAY` = WORLD_STATIC | DEVICES | PROPS | HEALTHY_PLAYERS | LIMP_BODIES | ELEVATOR.

Nothing sets layers or masks anywhere except `physics_layers.gd` (editor or `_ready`).

---

## Build a room scene

Room scenes live at `res://rooms/<name>.tscn` and are instanced into `res://world.tscn` as `Apartment` (x=0), `Casino` (x=100), `Rest` (x=50). Node-path contracts (kept unchanged — `world.gd` and tests depend on them):

- `Apartment`, `Casino`, `Rest` (Node3D)
- `Apartment/Elevator`, `Rest/Elevator`, `Casino/Elevator`
- `Apartment/NicknameTerminal`, `Apartment/JoinTerminal`, `Apartment/LobbyConsole`, `Apartment/ColorBoard`, `Apartment/PlayerBoard`
- `Rest/StatusBoard`
- `Spawn` markers (inside each room)
- `Casino/ChickenCross`, `Casino/Cluckjack`
- `Players`, `MultiplayerSpawner` (spawn path `../Players`)
- `HUD`, `WorldEnvironment`, `DirectionalLight3D`

Steps:

1. **Instance the room into `world.tscn`.** In `world.tscn`, add a `Node3D` child named `Apartment`/`Casino`/`Rest` at the contract transform (x = 0 / 100 / 50). Instance `res://rooms/<name>.tscn` into it.
2. **Build the shell.** Floor (StaticBody3D + collision), four walls, roof opening at the lift. Use mesh + StaticBody3D or baked CSG — prefer static over live CSG (perf budget: ≤ 20 awake rigid bodies, ≤ 4 shadow lights).
3. **Add lights & text.** OmniLight3D positions/colors/energies from `ENVIRONMENT_MIGRATION.md`. Label3D for room title and flavor text.
4. **Add props.** `PhysicsProp` instances (hand-placed, group `physics_props`, profile assigned). Each prop inherits `res://props/base_prop.tscn` — see "Prop kit" below.
   - Furniture and lore plaques are **temporarily out of scope** for rooms. Instructions/lore will be delivered via a TV/slideshow screen device instead of `LorePlaque` plaques — that device is TBD, do not add plaques.
5. **Add the Elevator.** Instance `res://elevator/elevator.tscn` as `Elevator` inside each room. `world.gd` reads `$Apartment/Elevator` etc. and connects `ride_requested`.
6. **Verify.** Run `./tests/run_checks.ps1` headless; fix regressions; commit.

**Success:** `test_house.tscn` passes all checks (roof collisions, window panes, lift openings clear, tables leave central aisle, 18+ physics_props, throw-speed tuning 3.0→14.0). No `LorePlaque` or furniture nodes in room scenes.

---

## Prop kit

Props are authored once as palette scenes under `res://props/`, each inheriting `res://props/base_prop.tscn`, then placed into rooms as instances.

| File | item_name | can_pick_up | Profile | Notes |
|------|-----------|-------------|---------|-------|
| `prop_moving_box.tscn` | Moving box | ON | `light_prop.tres` | carryable |
| `prop_last_clean_cup.tscn` | Last clean cup | ON | `light_prop.tres` | carryable |
| `prop_carton.tscn` | Empty takeaway carton | ON | `light_prop.tres` | carryable |
| `prop_radio.tscn` | Battered radio | ON | `light_prop.tres` | carryable |
| `prop_pillow.tscn` | Threadbare pillow | ON | `light_prop.tres` | carryable |
| `prop_chair.tscn` | Old chair | OFF | `heavy_prop.tres` | push-only |

Profiles live at `res://resources/profiles/light_prop.tres` (LIGHT, pickup/throw) and `res://resources/profiles/heavy_prop.tres` (HEAVY, no pickup/throw).

**Base prop scene** (`res://props/base_prop.tscn`): root `RigidBody3D` with script `res://interaction/physics_prop.gd`, `collision_layer = 4` (PROPS), `collision_mask = 53`, `CollisionShape3D` + `PropMesh` children. No `Interactable` child in the scene — `physics_prop.gd._ready()` adds it at runtime (kind derived from `can_pick_up`).

**Kit scenes** under `res://kit/`: `wall.tscn`, `window.tscn`, `floor.tscn`, `roof.tscn`. Each is a `StaticBody3D` with `CollisionShape3D` + `MeshInstance3D`, `collision_layer = 1` (WORLD_STATIC), `collision_mask = 53`. Instance into rooms and scale per placement.

---

## Run the checks

PowerShell (run from `dev-fowl-play`):

```powershell
./tests/run_checks.ps1 -GodotPath 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
```

Single test headless (Godot path required — if you can't run Godot from your shell, ask the user to run it and paste output):

```
godot --headless --path res://tests/test_house.tscn --quit-after 120
```

Exit code 0 = pass. Headless output is buffered until exit; redirect to a file if you need to read it.

---

## Late-join prop sync

When a new client joins mid-run, props already moved by the host (or another client) still render at their scene home positions on the joining client, so the new client can't interact with them until the host grabs them.

`carry_registry.gd` gains `_send_prop_state_to_peer(peer_id)` — host-only, iterates the `physics_props` group and sends each prop's `name` + `global_transform` + carry `holder_id` to that one peer via `_prop_state_sync.rpc_id`. The client matches props by name (names replicate; instance ids don't) and sets `global_transform` plus `BodyPhys.last_synced_transform` so interpolation starts from the real position.

`network.gd` calls `CarryRegistry._send_prop_state_to_peer(id)` at the end of `_on_peer_connected(id)` (host side).

**Success:** a joining client sees every prop at its current position and can pick it up / push it immediately; carried props also sync their holder so the carry relationship is visible from the first frame.

---

## Multiplayer playtest (every slice ends with one)

Two Godot instances on the same machine:

1. **Host:** launch with `--is-host` (or run the host instance normally; `test_house_network.tscn` detects `--is-host` in cmdline args).
2. **Client:** join `127.0.0.1` on port 17778 (ENet, UDP 7777 in the real game).
3. **Try:** pickup → single-slot rejection → charged throw clamp to 14.0 → disconnect cleanup.
4. **Should happen:** host prints "House ENet host: PASS …"; client prints "House ENet client: PASS …".

If it errors: check which node, which panel, paste the Output panel error text. Don't guess.

---

## Git

Local commits per logical slice, ending with `Co-Authored-By: Claude Code <noreply@anthropic.com>`. No push, no `reset --hard`, no `checkout --`, no force push, no `clean`, no `rm -rf .godot`.
