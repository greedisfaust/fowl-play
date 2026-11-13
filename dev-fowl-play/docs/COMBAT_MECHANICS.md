# COMBAT_MECHANICS.md — Punch / Parry / Limp behavior contract

Describes the intended feel and rules for Q punch, F parry, and limp state. Use this as the reference when playtesting or changing combat code.

## 1. Charge Punch (Hold Q)

**Input**: `InputMap` action `punch` (KEY_Q).

| Phase | Trigger | What happens |
|---|---|---|
| Press | Q pressed down | `combat.set_punch_charge_held(true, now)` starts the charge timer |
| Hold | Q held | Timer accumulates in `_punch_input_active` |
| Auto-fire | Q held ≥ `PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS` (1.0s) | Charged punch fires automatically while still holding Q. `_punch_charge_auto_fired` set so it only fires once per press. |
| Release | Q let go before 1s | If held ≥ 150ms: charged punch with charge = held_ms / 1000ms (clamped 0..1). If held < 150ms: light jab (jiggle only, **no limp state** — quick punch shouldn't ragdoll). |

**Why**: The user wants the charged punch to trigger at exactly 1 second of hold, not just on release. Auto-fire happens in `player.gd:_process()` every frame while `_punch_input_active` is true and `_punch_charge_auto_fired` is false.

**Charge value**: `clampf(held_ms / PUNCH_CHARGE_MS, 0.0, 1.0)` where `PUNCH_CHARGE_MS = 500` (player.gd const) — but auto-fire waits the full 1.0s per `PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS`.

**Can't punch while**: carrying anything, limp, or `carrier.is_carrying()` (`combat.can_start_punch_charge()` guards all of these).

## 2. Charged Punch — Lunge + Camera Arc

**Lunge**: when charge ≥ 1.0, `combat.start_lunge(direction, LUNGE_SPEED_MPS, 0.5)` stores a launch velocity in `Combat._lunge_velocity` with a 0.5s expiry. Direction is `-camera.global_basis.z` (forward from where the player is looking).

**Preserved through flight**: `player.gd:_physics_process()` checks `combat.is_lunging(now)` and, while true, sets `velocity.x/z` from `combat.lunge_velocity()` instead of reading move input. After `_lunge_until` expires, normal movement input resumes.

**Camera arc (steer)**: while lunging, `combat.steer_lunge(-(camera.global_basis.z), 0.0, 3.0)` pulls the lunge velocity toward wherever the camera is looking, capped at `max_turn_rad_per_sec = 3.0` rad/s. This lets the player arc the punch left/right mid-lunge by looking that way, but the turn rate is limited so a quick flick can't instantly aim behind. The movement still goes forward; the aim direction bends gradually toward camera look.

**Range**: `PUNCH_RANGE_M = 3.0` — `combat.validate_punch()` rejects targets farther than 3m.

## 3. Parry (F)

**Input**: `InputMap` action `parry` (KEY_F).

| Phase | Trigger | What happens |
|---|---|---|
| Press | F pressed | `combat.start_parry(now)` sets `_parry_active_until = now + PARRY_GRACE_SECONDS` (1.5s). `hands.set_guard(true)` tweens both hands smoothly (0.18s) into boxer-guard pose in front of the face. |
| Hold | F held | Guard stays active until `_parry_active_until` expires or F is released |
| Release | F let go | `hands.set_guard(false)` tweens both hands smoothly (0.18s) back to rest pose |

**Guard state cooldown**: after `_parry_active_until` expires, `_parry_cooldown = PARRY_COOLDOWN_SECONDS` (1.5s) before F can parry again. The guard stays up while F is held; releasing F relaxes the hands back to rest.

**Can't parry while**: limp, carrying, or during cooldown (`combat.can_start_parry(now)` checks `_parry_cooldown <= 0.0 and now >= _parry_active_until`).

**Parry success**: if target is parrying when a punch lands:
1. `combat.expire_parry(now)` — ends grace, starts cooldown
2. `parry_riposte.rpc_id(1, attacker_id)` — host knocks the attacker down (limp + launch)
3. Target shows "PARRIED!" notice

**Parry visual**: `hands.set_guard()` now tweens both hands smoothly in/out instead of snapping. It kills any in-flight guard tween when state changes, so rapid press/release won't glitch. Both hands move together to front-of-face pose (palms forward) and relax back together — no left-hand-only glitch.

## 4. Limp (knockdown / carried / thrown)

**States** (`PlayerState.LimpPhase`): `LIMP_GROUND` → `LIMP_CARRIED` → `LIMP_THROWN` → recovery to `IDLE`.

**Duration**: `PhysicsTuning.LIMP_SECONDS = 2.5` for charged punch and parry-riposte; 0.35s for jab.

**Authority**: host simulates the limp body via `BodyPhys.set_limp_mode()` + `apply_launch()`. Clients freeze + interpolate snapshots. The client never fabricates a launch.

**Recovery**: `BodyPhys.limp_recovered` signal fires when the limp timer expires → `_on_limp_recovered()` → `clear_limp_mode()` → `transition_to(IDLE)`.

**Can't interact while limp**: `_try_interact()` returns early if `state.is_limp()`. `_carry_input()` returns early if `limp_phase == LIMP_CARRIED`.

## 5. RPC flow (host-authoritative)

```
Client (press Q)   →  combat.set_punch_charge_held(true, now)   [local only]
Client (release Q) →  punch_request.rpc_id(1, target_peer, charge)  → host
Host (punch_request) → validate_punch(reach/state) → if valid:
  - Host applies limp mode + launch to target's BodyPhys directly
  - take_punch.rpc_id(target_id, sender, charge, is_charged)  → target client
Target client (take_punch) → state machine + visuals only (limp, jiggle, notice)
```

**Validation**: `punch_request` accepts sender -1 (host local call) or peer 1 (host); rejects everything else. `take_punch` and `parry_riposte` reject any sender that isn't host (peer 1) or server.

## 6. Files

- `res://player/player.gd` — `_combat_input`, `_combat_do_light_jab`, `_combat_throw_charged_punch`, `punch_request`, `take_punch`, `parry_riposte`, auto-fire in `_process`, lunge velocity preservation in `_physics_process`
- `res://player/combat.gd` — `start_lunge`, `is_lunging`, `lunge_velocity`, `steer_lunge`, `apply_ragdoll` (state+visuals only, no physics launch), parry state
- `res://player/hands.gd` — `set_guard()` (boxer-guard visual; OUT OF SCOPE per CLAUDE.md — hooks only, never change its look)
- `res://player/player_state.gd` — LIMP state machine, transitions, limp_timer
- `res://autoload/body_phys.gd` — `set_limp_mode`, `clear_limp_mode`, `apply_launch`, `limp_recovered` signal
- `res://scripts/physics_tuning.gd` — all timing/speed constants with units in names

## 7. Playtest checklist

- [ ] Tap Q (fast release <150ms) → jab, target jiggles, no limp, recovers instantly
- [ ] Hold Q ≥ 1s → charged punch auto-fires while still holding
- [ ] Hold Q, look left/right during lunge → punch arcs toward camera look
- [ ] Hold F → hands come up in boxer guard, "PARRY READY" notice
- [ ] F parry + get punched → attacker knocked down instead, "PARRIED!" notice
- [ ] Charged punch hit → target goes limp for 2.5s, head slumps, frozen input
- [ ] Jab hit → target jiggles, brief input unlock, recovers instantly
