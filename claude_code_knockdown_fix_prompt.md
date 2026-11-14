# Fowl Play — Fix the charged-punch knockdown (limp body) physics
### Diagnosis from the uploaded code + exact edits + tests, for Claude Code

> Paste everything below into Claude Code. Godot 4.7.2, typed GDScript (explicit static types, no `:=` inference traps, Python-style `a if cond else b` only), host = peer 1, host-authoritative. **Do not change** economy, table rules, lobby logic, or how `hands.gd` looks (hooks only).
> I (the user) am in the Godot editor. Where a step is an editor step, give me an **Editor Task Card** (click-by-click) instead of hand-editing `player.tscn`. Ask me if anything is unclear. Never edit a scene I have open.

---

## 1. Goal and acceptance numbers

A **charged punch** makes the victim go **limp** (knockdown = ragdoll = one concept): a physical body that flies a **reasonable arc** (about 5.4 m/s forward and 2.7 m/s up, from `CHARGED_PUNCH_PUSH_SPEED_MPS = 6.0` and a 0.5 lift ratio), tumbles and slides to rest, and **recovers after `LIMP_SECONDS` = 2.5 s** (only once it has come to rest). It must never fly away, sink under the floor, or fall into the void. **Host and clients must show the same thing.**

**Later requirement the design must already support (do not break it):** a limp player is a GRAB interactable. Another player can pick them up and carry them around. While carried, the limp timer is paused (they cannot wake up), and the **carried player can still move their camera to look around** in front of the carrier. They cannot move or act.

Measurable acceptance (host-only run AND host + client ENet run):
- peak body speed ≤ 8 m/s; horizontal travel from the hit point 2–8 m; max height gain ≤ 1.5 m;
- body `y` never below the floor by more than 0.5 m; no NaN/inf; never beyond the kill plane;
- state is LIMP on **every** machine (host, victim, observer) within 0.2 s of the hit, and IDLE on every machine within `LIMP_SECONDS` to `LIMP_MAX_SECONDS` after it;
- the victim's root position on the client is within 0.25 m of the host's at 1 s after the hit and at recovery;
- after recovery the limp body is **dormant** (frozen, no collision, zero velocity) and the player has control at the body's final position.

---

## 2. Findings: verdict on the four suspected causes

| Suspected cause | Verdict | Evidence in the uploaded code |
|---|---|---|
| **Double force** (host applies the launch, then `receive_knockdown` applies it again) | **Refuted in this version** | `player.gd:382` `receive_knockdown` no longer sets any velocity. The launch is applied once, in `punch_hitbox.gd:_hit_player`. (The host's `set_limp_mode` can run twice for a host victim; harmless.) |
| **Client velocity conflicts with frozen BodyPhys** | **Refuted as stated, but the real client bug is worse** | Same as above: no velocity is set. The problem is that the knockdown never reaches anyone except the victim (see RC-4). |
| **`last_synced_transform` snaps to origin** | **Confirmed (partly)** | `body_phys.gd` declares `last_synced_transform = Transform3D.IDENTITY` and every client `_physics_process` lerps toward it from spawn. It is only initialised for the victim in `receive_knockdown`. Sleeping bodies stop sending snapshots, so there is also no final settle packet. |
| **Conflicting vertical forces (dir.y)** | **Refuted** | `punch_hitbox.gd:_hit_player` zeroes `dir.y` first, then builds `Vector3(dir.x, 0.5, dir.z).normalized()`. That is a clean 27° launch. The numbers are fine. The bugs are structural. |

## 3. Root causes (ranked)

**RC-1: the player's `BodyPhys` is a child of the Player and never goes dormant (`player.gd:33`, `body_phys.gd:_physics_process`).**
It is not `top_level`, and on the host it is **unfrozen every frame** (`freeze = false` whenever not carried) for every player, limp or not. While limp, the player root is then moved to the body each frame (`player.gd:589` `global_position = body_phys.global_position`). A physics body that is a child of the node you keep teleporting to it is dragged by that same offset again each frame. That is a positive feedback loop, so the body runs away (to oblivion) and, at large coordinates, floats lose precision (camera spin, "pixel corruption"). *(Inferred from the code; confirm with the test in section 5 before fixing.)*

**RC-2 (very likely, verify in `player.tscn`): two overlapping colliders.**
The player capsule (CharacterBody3D) and the BodyPhys capsule overlap exactly and share a parent. The comment in `punch_hitbox.gd` ("one hit per player, even if they have several bodies") confirms the player has several collidable bodies. Overlapping, penetrating colliders produce depenetration impulses: vibration and flinging.

**RC-3 (verify): the limp body may have no collision shape, or a mask that misses the world.**
If so it free-falls: this is "client falls straight down into the void and sees the Apartment above". Check `BodyPhys` in `player.tscn`: it needs a `CollisionShape3D` (same capsule as the player) and a mask that includes world static.

**RC-4: the knockdown only reaches the victim's machine (`punch_hitbox.gd:_hit_player`, `combat.gd:_recoil_puncher`).**
`root.rpc_id(victim_id, "receive_knockdown", ...)` runs on the victim only. The host never sets the victim's `PlayerState` to LIMP (it only calls `victim_bp.set_limp_mode` directly), and observers never learn about it. Consequences:
- the host's copy of a client victim, and other clients' copies, run the non-authority branch (`player.gd:579`) which lerps to `_net_pos` and **ignores BodyPhys**. Nobody but the victim sees them move;
- the carrier's machine never sees the target as LIMP, so GRAB on a limp player cannot work;
- there are **three independent recovery timers** (host BodyPhys, victim BodyPhys, and the `_process` timer in `player.gd:427`) that can disagree. This is "sometimes doesn't recover".

**RC-5: snapshot gaps.** Snapshots are `unreliable_ordered` only, stop when the body sleeps, and there is no final reliable "settled" packet. `_physics_process` also sends a snapshot **every frame** while carried.

**RC-6: carry breaks networking (`player.gd:pickup/release`).** `pickup` **reparents the Player node** (`holder.add_child(self)`), which changes `Players/<id>` and breaks every RPC path, `_player_node(id)` and the MultiplayerSpawner. It also sets `Input.mouse_mode = MOUSE_MODE_VISIBLE` (the carried player **cannot look around**) and forces `head.rotation.x = 60°`.

**RC-7: no sender validation.** `receive_knockdown`, `receive_jiggle`, `_net_punch_hitbox`, `_net_parry` were changed to `any_peer` (to fix the "authority" error) but accept calls from any peer. Any client could knock down anyone. `punch_request` / `parry_request` / `parry_end_request` do not check that the sender owns the node.

**RC-8: no safety net.** No speed clamp, no kill plane, no guaranteed recovery cap.

**Smaller items to fix while you are in these files:**
- `PhysicsProp` IMMOVABLE sets `freeze = true`, but `BodyPhys._physics_process` forces `freeze = false` on the host every frame (immovable props are unfrozen).
- `PhysicsProp._ready` overrides `BodyPhys._ready` without `super()`. Verify that BodyPhys `_ready` actually runs for props (that is where `last_synced_transform` should be initialised). If it does not, props on clients drift toward the origin. Call `super()` or move the initialisation.
- `player.gd:617` compares `now` (absolute seconds) with `state.limp_timer` (a duration). Remove it.
- `receive_jiggle` sets `velocity` but never feeds `_jiggle_velocity`, so the jiggle spring is dead code.
- `player.gd` is CRLF while the repo is `eol=lf`; `body_phys.gd` has mojibake (`â€”`) from a wrong-encoding save. Normalize to UTF-8 / LF.

---

## 4. Target design: one flow, host decides, everyone mirrors

```
punch_hitbox (host)  ->  victim.host_knock_down(flat_dir, speed, seconds)     [host only, one entry point]
                           -> _net_limp_begin.rpc(start_pos, launch, seconds)  [reliable, call_local, host-only sender]
every machine: state=LIMP, input locked, root collision OFF, body_phys.begin_limp(...)
host BodyPhys: simulates flight; sends snapshots (unreliable_ordered) + one reliable "settled" packet
every machine: root follows body_phys.global_position  (clients' body already interpolates snapshots)
host BodyPhys: timer <= 0 AND settled (or hard cap) -> limp_recovered
host player:   _net_limp_end.rpc(final_pos)                                    [reliable, call_local]
every machine: state=IDLE, root collision ON, body dormant, control returns at final_pos
```

Rules:
1. **BodyPhys of a player is `top_level` and dormant** (frozen, collision disabled) unless limp. A limp body is activated at the player's exact transform, simulated only on the host.
2. **Only the host has a limp timer.** Remove the client BodyPhys timer and the `_process` recovery.
3. **The root never moves the body; the body moves the root** (all machines, while limp). The owner keeps mouse-look (yaw/pitch), and keeps sending `_net_state` so observers see where they look.
4. **The root capsule's collision is disabled while limp** (the limp body's capsule is the physical one). The limp body is on the focus-ray layer so it is GRAB-able, and does not collide with the player layer.
5. **Never reparent a Player node.** Carry = `BodyPhys` carry mode following the carrier's head anchor.
6. Every `any_peer` RPC validates the sender (`0` or `1` for host-only RPCs; `== str(name).to_int()` for requests that must come from the owner).

---

## 5. Step 0: reproduce first (test-first)

Before changing behavior, add a **failing** headless test (`tests/test_knockdown.gd` + `.tscn`, wired into `run_checks.ps1`) that spawns two players in the test world, calls the host entry point (initially emulate it by calling `_hit_player` or `set_limp_mode` + `apply_launch` on the victim's BodyPhys), steps ~4 s of physics frames, and asserts the acceptance numbers from section 1. Print body and root positions every 0.25 s. Confirm RC-1/RC-2/RC-3 from the output and record which ones were real in `docs/OVERHAUL_LOG.md`. Then fix until it passes. Then add the ENet host + client version (like `test_house_network`).

---

## 6. Edits

### 6.1 Editor Tasks for me (`player.tscn`): send me these cards, do not edit the scene yourself while I have it open
1. **BodyPhys node:** confirm the child is `BodyPhys` with script `body_phys.gd`. Add a `CollisionShape3D` child (CapsuleShape3D, radius 0.4, height 1.8, position `(0, 0.9, 0)`), identical to the player's. Tick **Top Level** (Node3D section; the code also sets it).
2. **Collision layers for BodyPhys** (tell me the exact layer names from `PhysicsLayers`): on the **focus-ray layer** (the same one `PhysicsProp` uses, `collision_layer = 4`), **mask = world static + props, NOT the player's own layer**.
3. **Physics material:** create `res://resources/limp_body.tres` (PhysicsMaterial, friction 0.9, bounce 0.05) and assign it to BodyPhys `Physics Material Override`.
4. Report the `player.tscn` node tree and the BodyPhys inspector values back to me so you can confirm RC-2/RC-3.

### 6.2 `scripts/physics_tuning.gd`: add

```gdscript
# --- limp body safety and feel ---------------------------------------------
const CHARGED_PUNCH_LIFT_RATIO: float = 0.5   # vertical share of the knockdown launch (about 27 degrees up)
const BODY_MAX_SPEED_MPS: float = 20.0        # hard speed clamp for any simulated body
const BODY_KILL_PLANE_Y_M: float = -10.0      # below this a body is returned to its last safe spot
const LIMP_SETTLED_SPEED_MPS: float = 1.0     # a limp body below this speed counts as at rest
const LIMP_MAX_SECONDS: float = 6.0           # hard cap of free tumbling: recovery ALWAYS happens
const LIMP_TUMBLE_SPIN_RADPS: float = 3.0     # tumble spin added to a knockdown
const SNAPSHOT_FOLLOW_RATE: float = 12.0      # client smoothing toward host snapshots (1/s)
const LIMP_CAMERA_HEIGHT_M: float = 0.5       # owner's camera height while lying down

## Knockdown launch velocity: mostly horizontal, with a fixed upward share, never above BODY_MAX_SPEED_MPS.
static func knockdown_velocity(flat_dir: Vector3, speed: float) -> Vector3:
	var d: Vector3 = Vector3(flat_dir.x, 0.0, flat_dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	return Vector3(d.x, CHARGED_PUNCH_LIFT_RATIO, d.z).normalized() * minf(speed, BODY_MAX_SPEED_MPS)
```

### 6.3 `autoload/body_phys.gd`: replace with this (adapt names to the repo; `grep` first for anything that assigns `is_authority` or calls the old API)

Keeps the public API (`set_carry_mode`, `clear_carry_mode`, `set_limp_mode`, `clear_limp_mode`, `apply_body_impulse`, `apply_launch`, `limp_recovered`, `body_impact`, `last_synced_transform`). Adds `begin_limp` / `end_limp`.

```gdscript
extends RigidBody3D

class_name BodyPhys

## Physical-body foundation for props AND limp players.
## Host (peer 1) simulates. Clients freeze and follow host snapshots.
## A player's own BodyPhys is DORMANT (frozen, collision off) until the player goes limp.
## It is top_level so it never rides, or fights, its parent's transform.

signal body_impact(speed: float, position: Vector3)   # wall-slam VFX hook
signal limp_recovered(body: Node)                     # host only: limp timer ran out and the body is at rest

## True on the machine that simulates physics (the host). Derived, never assigned.
var is_authority: bool:
	get:
		return is_inside_tree() and multiplayer.is_server()

@export var immovable: bool = false   # never simulated (set by PhysicsProp for IMMOVABLE)

var is_player_body: bool = false      # auto-detected: child of a CharacterBody3D
var carry_mode: bool = false
var carry_anchor: Node3D = null
var carry_offset: Vector3 = Vector3.ZERO
var limp_mode: bool = false
var limp_timer: float = 0.0           # host only: seconds left before recovery
var last_synced_transform: Transform3D = Transform3D.IDENTITY
var last_synced_linear_velocity: Vector3 = Vector3.ZERO
var last_synced_angular_velocity: Vector3 = Vector3.ZERO

var _snapshot_time: float = 0.0
var _sent_settled: bool = false
var _limp_elapsed: float = 0.0        # free-tumble time; pauses while carried
var _safe_transform: Transform3D = Transform3D.IDENTITY

func _enter_tree() -> void:
	top_level = true                   # keeps the global transform; stops riding a parent
	is_player_body = get_parent() is CharacterBody3D
	freeze = true

func _ready() -> void:
	mass = PhysicsTuning.PROP_MASS_KG
	linear_damp = PhysicsTuning.LINEAR_DAMP
	angular_damp = PhysicsTuning.ANGULAR_DAMP
	gravity_scale = PhysicsTuning.GRAVITY_SCALE
	continuous_cd = true
	add_to_group("body_phys")
	set_multiplayer_authority(1)
	last_synced_transform = global_transform   # never start at the world origin
	_safe_transform = global_transform
	if is_player_body:
		_set_dormant(true)

# --- dormant / collision ------------------------------------------------------

func _set_collision_enabled(enabled: bool) -> void:
	for child in get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", not enabled)

func _set_dormant(on: bool) -> void:
	_set_collision_enabled(not on)
	if on:
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

# --- carry mode ---------------------------------------------------------------

func set_carry_mode(anchor: Node3D, offset: Vector3) -> void:
	carry_mode = true
	carry_anchor = anchor
	carry_offset = offset
	freeze = true
	_set_collision_enabled(false)      # a carried body must not push or block the carrier
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

## Leave carry mode. On the host, `launch` becomes the body's velocity (a throw).
func clear_carry_mode(launch: Vector3 = Vector3.ZERO) -> void:
	carry_mode = false
	carry_anchor = null
	carry_offset = Vector3.ZERO
	_set_collision_enabled(true)
	if limp_mode:
		limp_timer = PhysicsTuning.LIMP_SECONDS   # put down or thrown: stays down a while longer
		_limp_elapsed = 0.0
	freeze = immovable or not is_authority
	if is_authority and not immovable:
		linear_velocity = launch.limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
		angular_velocity = Vector3.ZERO
		sleeping = false

# --- limp mode ----------------------------------------------------------------

## Runs on EVERY machine so state matches. Only the host simulates and launches.
func begin_limp(start: Transform3D, launch_velocity: Vector3, seconds: float) -> void:
	limp_mode = true
	limp_timer = seconds
	_limp_elapsed = 0.0
	mass = PhysicsTuning.LIMP_MASS_KG
	global_transform = start
	last_synced_transform = start
	_safe_transform = start
	_sent_settled = false
	_set_collision_enabled(true)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if is_authority:
		freeze = false
		sleeping = false
		linear_velocity = launch_velocity.limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
		if launch_velocity.length() > 0.01:
			angular_velocity = Vector3.UP.cross(launch_velocity.normalized()) * PhysicsTuning.LIMP_TUMBLE_SPIN_RADPS
	else:
		freeze = true

## Runs on EVERY machine. The body goes dormant at `final`.
func end_limp(final: Transform3D) -> void:
	limp_mode = false
	limp_timer = 0.0
	mass = PhysicsTuning.PROP_MASS_KG
	global_transform = final
	last_synced_transform = final
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if is_player_body:
		_set_dormant(true)

# Compatibility wrappers (old callers / tests).
func set_limp_mode(seconds: float) -> void:
	begin_limp(global_transform, Vector3.ZERO, seconds)

func clear_limp_mode() -> void:
	end_limp(global_transform)

# --- impulses / launch ----------------------------------------------------------

func apply_body_impulse(direction: Vector3, speed: float) -> void:
	if is_authority and not immovable:
		apply_central_impulse(direction.normalized() * speed)
		sleeping = false

func apply_launch(direction: Vector3, speed: float) -> void:
	if is_authority and not immovable:
		linear_velocity = (direction.normalized() * speed).limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
		angular_velocity = Vector3.UP.cross(direction.normalized()) * PhysicsTuning.LIMP_TUMBLE_SPIN_RADPS
		sleeping = false

# --- physics process -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_player_body and not limp_mode:
		return                          # dormant: a healthy player's body does nothing
	if carry_mode and carry_anchor != null:
		_carry_step(delta)
		return
	if not is_authority:
		_follow_snapshot(delta)
		return
	_host_step(delta)

func _host_step(delta: float) -> void:
	freeze = immovable
	linear_velocity = linear_velocity.limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
	if not global_position.is_finite() or global_position.y < PhysicsTuning.BODY_KILL_PLANE_Y_M:
		_return_to_safe()
		return
	var speed: float = linear_velocity.length()
	if speed < 0.5 and global_position.y > -1.0:
		_safe_transform = global_transform
	if speed > PhysicsTuning.IMPACT_SPEED_THRESHOLD_MPS:
		body_impact.emit(speed, global_position)
	if limp_mode:
		limp_timer -= delta
		_limp_elapsed += delta
		var settled: bool = speed < PhysicsTuning.LIMP_SETTLED_SPEED_MPS
		if (limp_timer <= 0.0 and settled) or _limp_elapsed >= PhysicsTuning.LIMP_MAX_SECONDS:
			_ready_to_recover()
			return
	_snapshot_time += delta
	if not sleeping:
		_sent_settled = false
		if _snapshot_time >= PhysicsTuning.get_snapshot_interval_seconds():
			_snapshot_time = 0.0
			_send_snapshot()
	elif not _sent_settled:
		_sent_settled = true
		_sync_settled.rpc(global_transform)       # one reliable packet when the body comes to rest
		last_synced_transform = global_transform

func _send_snapshot() -> void:
	_sync_snapshot.rpc(global_transform, linear_velocity, angular_velocity)
	last_synced_transform = global_transform
	last_synced_linear_velocity = linear_velocity
	last_synced_angular_velocity = angular_velocity

func _follow_snapshot(delta: float) -> void:
	var t: float = minf(delta * PhysicsTuning.SNAPSHOT_FOLLOW_RATE, 1.0)
	global_position = global_position.lerp(last_synced_transform.origin, t)
	quaternion = quaternion.slerp(last_synced_transform.basis.get_rotation_quaternion(), t)

func _return_to_safe() -> void:
	push_warning("BodyPhys %s left the world; returned to its last safe position." % name)
	global_transform = _safe_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false

## Host: carried body follows the carrier's head anchor (keep the existing wall raycast), but only
## send snapshots at the normal rate (not every frame).
func _carry_step(delta: float) -> void:
	# KEEP the current carry follow code here (anchor from the carrier's "Head", offset, wall raycast,
	# local lock on the carrier's own client, lerp on observers). Then, on the host only:
	#   _snapshot_time += delta
	#   if _snapshot_time >= PhysicsTuning.get_snapshot_interval_seconds():
	#       _snapshot_time = 0.0
	#       _send_snapshot()
	pass

## Host: the limp timer ran out and the body is at rest. Go dormant; tell the player.
func _ready_to_recover() -> void:
	var final: Transform3D = global_transform
	end_limp(final)
	_sync_settled.rpc(final)
	limp_recovered.emit(self)

# --- replication -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_snapshot(xform: Transform3D, lin: Vector3, ang: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_authority:
		return                          # only the host sends; the host ignores its own
	last_synced_transform = xform
	last_synced_linear_velocity = lin
	last_synced_angular_velocity = ang

@rpc("any_peer", "call_remote", "reliable")
func _sync_settled(xform: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_authority:
		return
	last_synced_transform = xform
```

Notes for you (Claude Code): (a) the `_carry_step` stub means "move the existing carry branch here unchanged, minus the per-frame RPC"; (b) if `PhysicsProp._ready` overrides without `super()`, make sure `last_synced_transform` and the group are initialised for props too; (c) in `PhysicsProp`, set `immovable = true` in the IMMOVABLE branch (instead of `freeze = true`); (d) `PhysicsProp._process` keeps its out-of-bounds return home, but `BodyPhys` now also has a kill plane, so keep only one of them.

### 6.4 `player/player.gd`

**`_ready`:** replace `body_phys.set_multiplayer_authority(...)` with nothing (BodyPhys sets authority 1 itself). Remember `_head_rest_y := head.position.y` and `_body_rest_transform := $Body.transform`. Connect `limp_recovered` as before; the handler is host-only.

**Delete** `receive_knockdown`, `apply_ragdoll`, the limp-recovery block in `_process` (lines ~425–432), the old `_on_limp_recovered`, and the line `now >= (state.limp_timer if ...)` in `_physics_process`.

**Add** the single limp flow:

```gdscript
# --- limp (knockdown) -----------------------------------------------------------
# HOST decides and simulates; every machine mirrors state through two reliable RPCs.

## HOST ONLY. The one entry point for knocking a player down (charged punch, parry recoil).
func host_knock_down(flat_dir: Vector3, speed: float, seconds: float) -> void:
	if not multiplayer.is_server() or state.is_limp():
		return
	_net_limp_begin.rpc(global_position, PhysicsTuning.knockdown_velocity(flat_dir, speed), seconds)

@rpc("any_peer", "call_local", "reliable")
func _net_limp_begin(start_pos: Vector3, launch: Vector3, seconds: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return                               # only the host may knock a player down
	if state.is_limp():
		return
	combat.cancel_lunge()
	combat.set_punch_charge_held(false, -1.0)
	_punch_input_active = false
	if carrier.is_carrying() and is_multiplayer_authority():
		carrier.request_drop(false)
	state.transition_to(PlayerState.State.LIMP)
	state.set_limp_phase(PlayerState.LimpPhase.LIMP_GROUND)
	_set_root_collision(false)
	body_phys.begin_limp(Transform3D(Basis.IDENTITY, start_pos), launch, seconds)
	input_locked = true

func _on_limp_recovered(body: Node) -> void:
	if body != body_phys or not multiplayer.is_server():
		return                               # host only: the single recovery clock
	_net_limp_end.rpc(body_phys.last_synced_transform.origin)

@rpc("any_peer", "call_local", "reliable")
func _net_limp_end(final_pos: Vector3) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not state.is_limp():
		return
	body_phys.end_limp(Transform3D(Basis.IDENTITY, final_pos))
	global_position = final_pos
	_net_pos = final_pos
	velocity = Vector3.ZERO
	_set_root_collision(true)
	state.set_limp_phase(PlayerState.LimpPhase.LIMP_GROUND)
	state.transition_to(PlayerState.State.IDLE)
	input_locked = false
	head.position.y = _head_rest_y
	head.rotation.x = 0.0
	head.rotation.z = 0.0
	$Body.transform = _body_rest_transform
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_root_collision(enabled: bool) -> void:
	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", not enabled)

## Every machine, every physics frame while limp: the root follows the body, never the reverse.
func _limp_puppet(delta: float) -> void:
	global_position = body_phys.global_position
	velocity = Vector3.ZERO
	_net_pos = global_position
	var mesh: Node3D = $Body
	mesh.global_basis = body_phys.global_basis                     # the tumble shows on the mesh
	mesh.global_position = body_phys.global_position + body_phys.global_basis * Vector3(0.0, 0.9, 0.0)
	if is_multiplayer_authority():
		# The owner can still look around (mouse look runs in _unhandled_input). Lower the camera.
		head.position.y = move_toward(head.position.y, PhysicsTuning.LIMP_CAMERA_HEIGHT_M, 4.0 * delta)
		_net_state.rpc(global_position, rotation.y, head.rotation.x)
	else:
		rotation.y = lerp_angle(rotation.y, _net_yaw, 0.3)
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, 0.3)
```

**`_physics_process`:** make the limp case the **first** statement (before the `not is_multiplayer_authority()` branch) so every machine puppets:

```gdscript
func _physics_process(delta: float) -> void:
	if state.is_limp():
		_limp_puppet(delta)
		return
	# ... existing code (non-authority interpolation, movement) unchanged ...
```
and delete the old limp branch inside it.

**Carry (`pickup` / `release`): no reparenting, mouse stays captured:**

```gdscript
# Called on every machine when another player starts carrying this limp player.
func pickup(holder: Node) -> void:
	state.set_limp_phase(PlayerState.LimpPhase.LIMP_CARRIED)
	body_phys.set_carry_mode(holder as Node3D, get_carry_offset())
	# NO reparenting (it breaks Players/<id> and every RPC path). NO mouse release: a carried
	# player can still look around in front of the carrier. The limp timer is paused by BodyPhys.

func release(throw: bool, direction: Vector3, speed: float) -> void:
	state.set_limp_phase(PlayerState.LimpPhase.LIMP_THROWN if throw else PlayerState.LimpPhase.LIMP_GROUND)
	body_phys.clear_carry_mode(direction.normalized() * speed if throw else Vector3.ZERO)
	# BodyPhys restarts the limp timer (LIMP_SECONDS) so they stay down after being put down or thrown.
```
Adapt `CarryRegistry` / `Carrier` so they call these on every machine via the existing `hold_begin` / `hold_end` signals (I cannot see those files: read them, then wire it).

**Sender validation** (add at the top of each):
- `punch_request`, `parry_request`, `parry_end_request`: `var sender: int = multiplayer.get_remote_sender_id(); if sender != 0 and sender != str(name).to_int(): return` (the requester must own the node).
- `receive_jiggle`, `_net_punch_hitbox`, `_net_parry`: `if sender != 0 and sender != 1: return` (host-only).

### 6.5 `player/punch_hitbox.gd`: `_hit_player` becomes one path

```gdscript
func _hit_player(root: Node3D) -> void:
	var dir: Vector3 = root.global_position - origin
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else _flat_forward()
	print("PUNCH HIT: victim=", str(root.name), " quick=", is_quick, " speed=", push_speed)
	if is_quick:
		root.rpc("receive_jiggle", dir)
		return
	root.call("host_knock_down", dir, push_speed, ragdoll_seconds)   # the single knockdown path
```
(Remove the direct `victim_bp.set_limp_mode / apply_launch` calls and the `receive_knockdown` RPC. If you add `class_name Player` to `player.gd`, replace `root.call(...)` with a typed call.)

### 6.6 `player/combat.gd`: parry recoil uses the same path

```gdscript
# in _recoil_puncher(), replace the rpc_id line:
	puncher.call("host_knock_down", dir, PARRY_RECOIL_SPEED_MPS, PARRY_RECOIL_SECONDS)
```
Delete `Combat.apply_ragdoll` (now duplicated); update anything that called it (tests).

### 6.7 Cleanup outside these files
- Check `PlayerState`: `transition_to(IDLE)` from LIMP must be legal (bypass), and `LimpPhase` values exist. Remove `limp_timer` state data if nothing else needs it (the host BodyPhys owns the clock).
- Check `Focus` and `Interactable.find`: a limp player must be a GRAB target through the **BodyPhys collider** (parent chain reaches the player root) and healthy players must not be.
- Update `tests/test_house.gd` (and anything calling `receive_knockdown`, `apply_ragdoll`, `set_limp_mode`) to the new API. **Never delete a check without porting it.**

---

## 7. Tests (add; the host-only one is test-first)

**`tests/test_knockdown.gd` (headless, host only):** two players; call `victim.host_knock_down(Vector3.FORWARD, 6.0, 2.5)`; sample 4 s of physics frames. Assert every number in section 1: speed, travel, height, floor, finite, LIMP on the victim within 0.2 s, IDLE by `LIMP_SECONDS` to `LIMP_MAX_SECONDS`, body dormant after, root at body position, root capsule collision re-enabled. Also: (1) a **host victim** and a **client victim** case, (2) knocking down an already-limp player is ignored, (3) a body forced below `BODY_KILL_PLANE_Y_M` returns to its last safe position, (4) a limp player carried for 10 s does **not** recover, then recovers `LIMP_SECONDS` after being put down, (5) carrying a limp player never changes its node path, (6) a client-sent `_net_limp_begin` is rejected.

**ENet host + client (extend `test_house_network.gd` or a sibling):** client victim; both processes report root and body positions and state to each other; assert LIMP on both, positions within 0.25 m at 1 s and at recovery, IDLE on both within the window.

**Manual playtest (I will run it; give me a Playtest Request):** host punches client, client punches host, client punches client (3 players if possible), at a wall, at the edge of a rug, and in the elevator doorway; then pick a limp player up, look around, drop, throw. Report anything that flies, sinks, vibrates, or stays down.

---

## 8. Order of work and reporting

1. Read the files in section 3 plus `player.tscn`, `CarryRegistry`, `Carrier`, `PlayerState`, `Interactable`, `PhysicsLayers`. Run the headless tests for a baseline.
2. Section 5: write the failing test, run it, and report which of RC-1/2/3 reproduced.
3. Send me the Editor Task Cards (6.1). Continue with script work that does not depend on them.
4. Implement 6.2 → 6.6, then 6.7, running `test_knockdown` after each step.
5. Full suite (`run_checks.ps1`), then a Playtest Request for me.
6. Commit locally per step (no push), update `docs/OVERHAUL_LOG.md`, `docs/INTERACTION.md`, `docs/STATUS.md`, and list anything **unverified** (anything that needed the real editor, real input, or two live machines).

If something here conflicts with what you find in the real files (several I have not seen), **tell me and propose the alternative** instead of forcing it.
