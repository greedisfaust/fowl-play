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
