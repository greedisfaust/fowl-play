# Fowl Play — Feature Implementation Onboarding Brief

AI introductory recap for the next feature implementation. Designed so a fresh session (or a new agent) can pick up work without re-reading the whole tree.

---

## 1. Project at a glance

**Fowl Play** — a Godot 4.7.2 (typed GDScript) local-multiplayer brawler/physics sandbox.

- **Networking:** host-authoritative ENet, UDP 7777 in the real game (17778 in the headless playtest scene). Host = peer 1; up to 3 clients.
- **Physics foundation:** `BodyPhys` (autoload) carries carry / limp / simulation state; `CarryRegistry` is the single source of truth for carried props/bodies.
- **Combat:** `Q` punch (charge → lunge → knockdown/limp or jab/jiggle), `F` parry (press-once, 1.5s guard, auto-expire), limp/ragdoll recovery state machine.
- **Branch:** `features/physics-overhaul-and-mechanics` (clean; all prior fixes committed in HEAD).
- **Teaching Mode:** `CLAUDE.md` governs editor work as click-by-click EDITOR TASK cards and SCRIPT HANDOFF CARDS. Follow it when touching scenes/nodes in the editor.
- **Git policy (user boundary):** local commits only on the feature branch; **no push, no `reset --hard`, no `checkout --`, no force push, no `clean`, no `rm -rf .godot`**. Commit messages end with `Co-Authored-By: Claude Code <noreply@anthropic.com>`.

---

## 2. Authority & RPC model (security-relevant)

| Concept | Rule |
|---|---|
| Host | peer 1 = `multiplayer.get_unique_id() == 1` on the host machine |
| RPC modes | `authority` = node owner only; `any_peer` = anyone, **must** validate `get_remote_sender_id()` |
| Timer ownership | **Host owns all timers**; clients report press/release only |
| Validation | Every `any_peer` RPC validates `get_remote_sender_id()` + state before acting |
| Self-RPC pitfall | Never RPC to yourself; detect `peer_id == multiplayer.get_unique_id()` and call the method locally instead |

Key nodes/RPCs to remember:
- `player.gd`: `teleport_to` (`any_peer`, `call_local`, reliable), `_net_parry` (`any_peer`, `call_remote`, reliable), `_net_lunge_stop` (targeted `.rpc_id(peer_id)`)
- `combat.gd`: host-authoritative punch/parry/knockdown logic; `parry_ended` signal tells everyone to drop guard
- `punch_hitbox.gd`: host-only hitbox; `body_entered` applies hit / stops lunge / recoils puncher

---

## 3. Core file map & how they connect

```
res://
├── player/
│   ├── player.gd                      # Player (CharacterBody3D). Input, RPCs, node mutations,
│   │                                   _process/_physics_process, lunge velocity preservation,
│   │                                   optimistic local parry + host broadcast.
│   ├── combat.gd                      # Combat (RefCounted). ALL punch/parry/knockdown STATE + LOGIC.
│   │                                   start/finish/cancel lunge, parry state, recoil, spawn hitbox.
│   ├── punch_hitbox.gd                # PunchHitbox (Area3D). Moving hitbox parented to puncher;
│   │                                   stops lunge on hit, applies knockdown/jiggle, host only.
│   ├── hands.gd                       # set_guard() boxer-guard visual (OUT OF SCOPE per CLAUDE.md —
│   │                                   hooks only, never change its look).
│   └── player_state.gd                # LIMP state machine (LIMP_GROUND → CARRIED → THROWN → IDLE).
├── autoload/
│   └── body_phys.gd                   # BodyPhys. set_limp_mode / clear_limp_mode / apply_launch /
│                                       limp_recovered signal; host simulates, clients interpolate.
├── scripts/
│   ├── physics_tuning.gd              # All timing/speed constants with units in names
│   │   (LUNGE_SPEED_MPS, CHARGED_PUNCH_*, PARRY_*, LIMP_SECONDS, PUNCH_RANGE_M …)
│   └── physics_layers.gd              # Collision layers/masks single source of truth
│                                       (WORLD_STATIC=1, DEVICES=2, PROPS=4, CARRIED=8,
│                                       HEALTHY_PLAYERS=16, LIMP_BODIES=32, ELEVATOR=64)
├── environment/
│   └── house_environment.gd           # _casino() Poker lookup guarded with get_node_or_null;
│                                       elevator teleport target.
├── interaction/
│   ├── physics_prop.gd                # PhysicsProp (BodyPhys). Carryable/push-only props;
│                                       adds Interactable at runtime.
│   └── interactable.gd                # Interactable component (kind GRAB / USE).
├── carry_registry.gd                  # Single source of truth for carried props/bodies;
│                                       late-join prop state sync.
├── network.gd                         # ENet host/client; peer connect/disconnect cleanup;
│                                       calls carry registry sync on peer join.
├── world.gd                           # Reads $Apartment/Elevator etc.; connects ride_requested.
├── rooms/*.tscn                       # Apartment / Casino / Rest (node-path contracts world.gd + tests depend on).
├── tests/test_house.tscn              # Headless check scene (run_checks.ps1).
└── docs/
    ├── BUILD_GUIDE.md                 # How to add props/devices/rooms + collision layers + playtest.
    ├── COMBAT_MECHANICS.md            # Combat behavior contract (punch/parry/limp/RPC flow).
    └── FEATURE_ONBOARDING_BRIEF.md    # this file.
```

**Connection summary:**
- `player.gd` owns the node + RPCs → delegates state/logic to `combat.gd` → `combat.gd` spawns `punch_hitbox.gd` (parented to puncher) and talks to `body_phys.gd` for limp/launch.
- Input (Q/F) lives in `player.gd`; `combat.gd` validates via `can_start_punch_charge()` / `can_start_parry()` / `can_do_light_jab()`.
- `BodyPhys.set_limp_mode()` + `apply_launch()` run on host; clients freeze + interpolate snapshots via `_net_limp_begin`/`_net_limp_end`.
- `CarryRegistry` / `network.gd` handle carried-prop sync and late-join state.

---

## 4. Combat flow (Q punch / F parry / limp)

### Charge punch (Q)
1. Press Q → `combat.set_punch_charge_held(true, now)` (local only).
2. Hold Q → timer accumulates; **auto-fires** at `CHARGED_PUNCH_HOLD_SECONDS` (1.0s) while still holding (`_punch_charge_auto_fired` guards double-fire).
3. Release Q before 1s → held ≥150ms: charged punch `charge = held_ms/1000ms` (clamped 0..1). Held <150ms: light jab (jiggle only, **no limp**).
4. Client release → `punch_request.rpc_id(1, target_peer, charge)` → host.
5. Host `validate_punch()` (range ≤ `PUNCH_RANGE_M`=3.0) → spawns moving hitbox via `combat.spawn_punch_hitbox()`, parents to puncher.
6. Hit applies: quick → `receive_jiggle`; charged → `host_knock_down` (limp + launch, ~2.5–3.5s).

### Lunge (charged punch)
- `combat.start_lunge(direction, LUNGE_SPEED_MPS, 0.5)`; `_physics_process` preserves `lunge_velocity()` while `is_lunging(now)`.
- `steer_lunge(camera look, 0.0, 3.0)` arcs toward camera look (max 3 rad/s).
- Hitbox moves with puncher for the full 0.5s.
- **Hit during lunge** → `finish_lunge()` (`_lunge_until=0`, velocity=ZERO) + `_net_lunge_stop.rpc_id(peer_id)` to puncher client (own copy stops locally — never self-RPC).
- **Nothing hit** → no damage; normal input resumes after expiry.
- **Hit by another charged punch mid-lunge** → `cancel_lunge()` aborts with no hit.

### Parry (F — press-once, 1.5s, no hold-to-keep)
1. Press F → optimistic local `combat.start_parry(now)` + `parry_request.rpc_id(1)`.
2. Host `_net_parry(parrier_id, true)` toggles state + spawns real barrier; replies to everyone.
3. Guard active until `_parry_active_until` (now + `PARRY_GRACE_SECONDS`=1.5s) expires or F released early.
4. On expiry → `expire_parry()` → `_end_parry()` → cooldown `PARRY_COOLDOWN_SECONDS`; `_parry_expired_notify` lets client owner report expiry.
5. Parry success (barrier blocks punch) → `on_parry_success()` recoils puncher (`host_knock_down` with `PARRY_RECOIL_SPEED_MPS`/`PARRY_RECOIL_SECONDS`), cancels punch, "PARRIED!" notice. Parry stays active for the grace window.
6. `set_parry_state()` **won't resurrect** an already-expired parry (late host reply guard).

### Limp (knockdown)
- Host: `BodyPhys.set_limp_mode()` + `apply_launch(dir, speed, seconds)`.
- Clients: freeze + interpolate snapshots; never fabricate a launch.
- Recovery: `limp_recovered` signal → `clear_limp_mode()` → `transition_to(IDLE)`.
- Can't interact / punch / parry while limp (`state.is_limp()` guards).

---

## 5. What was completed this session (already in HEAD)

- `teleport_to` RPC mode changed `authority` → `any_peer` (fixes clients stuck in lobby elevator not teleporting). `player/player.gd:792`
- `_net_parry` sender restriction removed; uses stored `p.hands` reference instead of `get_node_or_null("Head/Hands")` path search (fixes clients not seeing host parry animation). `player/player.gd:473,487`
- Press-once parry with optimistic local start + host broadcast; client owner can report expiry via `_parry_expired_notify`. `player/player.gd:333-350,519-532`
- `set_parry_state()` won't resurrect an expired parry. `player/combat.gd:173-181`
- `_net_lunge_stop` self-call error fixed: peer-is-self calls `finish_lunge()` locally instead of RPCing to self. `player/punch_hitbox.gd:80-91`
- `puncher_combat` `@export` removed (RefCounted can't be exported). `player/punch_hitbox.gd:19`
- `house_environment.gd` Poker null-deref crash fixed with `get_node_or_null("Poker")` guard. `environment/house_environment.gd:265-276`
- `docs/BUILD_GUIDE.md` — added "Charge punch (combat)" section (Q charge + auto-fire, jab, lunge + camera arc, moving hitbox, stop-on-hit, partial charge / nothing-hit outcomes, files + playtest criteria).

---

## 6. Errors hit & fixes applied (reference for next feature)

| Error / symptom | Root cause | Fix |
|---|---|---|
| `_net_lunge_stop` RPC "on yourself" | RPCing to self is illegal | Detect `peer_id == multiplayer.get_unique_id()`; call `finish_lunge()` locally |
| Client parry stuck state | Host-only parry, no client expiry path | Optimistic local `start_parry()` + `parry_request.rpc_id(1)`; client owner reports expiry via `_parry_expired_notify` |
| Clients don't see host parry animation | `get_node_or_null("Head/Hands")` path search fails on remote nodes | Use stored `p.hands` reference |
| Clients stuck in lobby elevator | `teleport_to` was `authority`-only | Changed to `any_peer` (validated) |
| `house_environment.gd` `_casino()` crash | `get_node("Poker")` returned null | `get_node_or_null("Poker")` guard |
| Parry resurrected after expiry | Late host reply re-activated `_parry_active_until` | `set_parry_state()` guards `active_until > 0 && _parry_active_until <= 0` → return |

---

## 7. Things learned / guardrails for the next feature

1. **Host owns timers.** Clients report press/release only; never let a client drive a cooldown or grace timer.
2. **Validate `any_peer` RPCs.** Always check `get_remote_sender_id()` (and state) before mutating.
3. **No self-RPC.** Guard `peer_id == multiplayer.get_unique_id()` and call locally.
4. **`@export` does not work on `RefCounted`.** `puncher_combat: Combat` is a plain `var`, not exported.
5. **Node-path lookups can fail on remote peers.** Prefer stored references (`p.hands`) over `get_node_or_null` path searches for replicated visuals.
6. **Parry is press-once, not hold-to-keep.** The 1.5s grace auto-expires; cooldown follows. Don't re-add hold behavior without updating `COMBAT_MECHANICS.md`.
7. **Hitbox must move with the lunge.** Parent it to the puncher (`parent_node.add_child(hitbox)`) so it connects mid-flight.
8. **Keep `docs/BUILD_GUIDE.md` and `docs/COMBAT_MECHANICS.md` in sync** with every slice (CLAUDE.md rule 10).
9. **Sandbox limits:** local git commits and Godot/headless test runs must be executed by the user, not the agent. Commit on `features/physics-overhaul-and-mechanics`, no push.

---

## 8. Pending work for the next feature

- **Commit** the staged `docs/BUILD_GUIDE.md` change (and any uncommitted working-tree fixes) on `features/physics-overhaul-and-mechanics`, ending with `Co-Authored-By: Claude Code <noreply@anthropic.com>` (user runs this).
- **Run headless checks:**
  ```powershell
  ./tests/run_checks.ps1 -GodotPath 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
  ```
  Single test: `godot --headless --path res://tests/test_house.tscn --quit-after 120` (exit 0 = pass).
- **Multiplayer playtest:** two Godot instances on one machine; host with `--is-host`, client joins `127.0.0.1:17778`. Verify teleport, parry visuals on host+client, charged-punch lunge + hit-during-lunge stop.
- **Update `docs/BUILD_GUIDE.md`** again once the next slice lands (per CLAUDE.md rule 10).
- Optional: update `docs/COMBAT_MECHANICS.md` if combat behavior changes.

---

## 9. How to run / test

From `dev-fowl-play`:

- **Headless check suite:** `./tests/run_checks.ps1 -GodotPath '<godot.exe>'`
- **Single headless test:** `godot --headless --path res://tests/test_house.tscn --quit-after 120`
- **Multiplayer playtest:** host instance (`--is-host`), client joins `127.0.0.1` port 17778.
- **Git:** `git status --short`, `git log --oneline -5`, `git branch --show-current` (branch: `features/physics-overhaul-and-mechanics`).
