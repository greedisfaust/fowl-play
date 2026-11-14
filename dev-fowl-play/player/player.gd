class_name Player extends CharacterBody3D

## Player node: thin coordinator (R9).
## Input -> component calls (Focus / Combat / Carrier / PlayerState), RPCs, node
## mutation. All carry/combat/limp state lives in the components - no loose
## `_carrier_id` / `_carried_player_id` / `_knocked_down_until` vars here.
##
## The player carries a `BodyPhys` child node (`$BodyPhys`) which owns the
## limp-physics simulation (knockdown / ragdoll / carried / thrown) when the
## host simulates the body. While limp, the host drives BodyPhys and the player
## root is synced to it; the owner's camera stays attached.

const SPEED := 5.0
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.003

# Re-exported for tests and callers that still reference them directly.
const PUNCH_CHARGE_MS := 500      # hold Q this long for a charged punch
const PARRY_COOLDOWN := 1.5       # seconds before F can parry again
const PARRY_GRACE := 1.5          # max seconds parry stays active while holding F
const PUNCH_RANGE := 3.0          # how far a charged punch reaches (bug #9)
const LUNGE_SPEED := 12.0         # how far a charged punch lunges the puncher

const Interactable := preload("res://interaction/interactable.gd")
const PhysicsProp := preload("res://interaction/physics_prop.gd")
const Overlay := preload("res://ui/interaction_overlay.gd")
const BodyPhys := preload("res://autoload/body_phys.gd")   # force class_name registration

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/RayCast3D
@onready var body_phys: BodyPhys = $BodyPhys

# --- network / interpolation state ---
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var hands: Hands
var overlay: InteractionOverlay
var _last_push := 0.0
var input_locked := false
var _q_press_time: float = -1.0   # Q press timestamp: throw charge / drop tap
var _punch_charge_auto_fired: bool = false   # true once charged punch auto-fired at 1s
var _head_rest_y: float = 1.6   # owner's eye height when standing
var _body_rest_transform: Transform3D = Transform3D.IDENTITY   # $Body rest transform
var _limp_yaw: float = 0.0   # accumulated mouse yaw while limp (applied on top of body tumble)
var _limp_pitch: float = 0.0 # accumulated mouse pitch while limp
var _hover_on := false
var _hover_point := Vector3.ZERO

# --- components ---
var state: PlayerState = PlayerState.new()   # explicit player state machine
var focus: Focus = Focus.new()               # local "what am I looking at"
var combat: Combat = Combat.new()            # punch / parry / knockdown / ragdoll
var carrier: Carrier = Carrier.new()         # single code path for item + limp-player carry
var _highlight: FocusHighlight = FocusHighlight.new()   # glow/outline on hovered target
var base_cam_rot: Vector3 = Vector3.ZERO     # base camera rotation (shaking resets to this each frame)

# --- jiggle spring (visual only: mesh lags behind body, then snaps back) ---
var _jiggle_offset := Vector3.ZERO
var _jiggle_velocity := Vector3.ZERO
const JIGGLE_STIFFNESS := 14.0
const JIGGLE_DAMPING := 0.6

# camera shake (visual only)
var _wall_hit_until := 0.0          # time until wall-hit stun expires
var _cam_shake_until := 0.0         # time until camera shake expires
var _cam_shake_intensity := 1.0

func host_knock_down(flat_dir: Vector3, speed: float, seconds: float) -> void:
	if not multiplayer.is_server() or state.is_limp():
		return
	var launch := PhysicsTuning.knockdown_velocity(flat_dir, speed)
	_apply_limb_begin(global_position, launch, seconds)   # host's own copy
	if multiplayer.multiplayer_peer != null:
		_net_limb_begin.rpc(global_position, launch, seconds) # clients mirror

# Shared body: put this machine's copy into limp. Called directly by host_knock_down
# (host) and by _net_limb_begin (clients). No RPC itself.
func _apply_limb_begin(start_pos: Vector3, launch: Vector3, seconds: float) -> void:
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
	# Seed limp yaw from where the player was facing; pitch starts at 0 so the
	# head doesn't snap to a mismatched local pitch (which caused the vertical flip).
	_limp_yaw = rotation.y
	_limp_pitch = 0.0

@rpc("any_peer", "call_remote", "reliable")
func _net_limb_begin(start_pos: Vector3, launch: Vector3, seconds: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return                               # only the host may knock a player down
	if state.is_limp():
		return
	_apply_limb_begin(start_pos, launch, seconds)

# Host only: BodyPhys limp timer expired. Single recovery clock.
func _on_limb_recovered(body: Node) -> void:
	if body != body_phys:
		return
	if not multiplayer.is_server():
		return                               # host only: the single recovery clock
	var final: Vector3 = body_phys.last_synced_transform.origin
	_apply_recovery(final)                   # host's own copy recovers
	_net_limb_end.rpc(final)                 # clients mirror

# Shared body: bring this machine's copy back to IDLE. Called directly by _on_limb_recovered
# (host) and by _net_limb_end (clients). No RPC itself.
func _apply_recovery(final: Vector3) -> void:
	body_phys.end_limp(Transform3D(Basis.IDENTITY, final))
	global_position = final
	_net_pos = final
	velocity = Vector3.ZERO
	_set_root_collision(true)
	state.set_limp_phase(PlayerState.LimpPhase.LIMP_GROUND)
	state.transition_to(PlayerState.State.IDLE)
	input_locked = false
	head.position.y = _head_rest_y
	head.global_position = global_position + Vector3(0.0, _head_rest_y, 0.0)
	head.rotation = Vector3.ZERO        # full reset: x, y, z all back to identity
	rotation.y = 0.0
	_limp_yaw = 0.0
	_limp_pitch = 0.0
	$Body.transform = _body_rest_transform
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

@rpc("any_peer", "call_remote", "reliable")
func _net_limb_end(final_pos: Vector3) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not state.is_limp():
		return
	_apply_recovery(final_pos)

func _set_root_collision(enabled: bool) -> void:
	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", not enabled)

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	var mine := is_multiplayer_authority()
	# BodyPhys sets authority itself (peer 1) in _ready.
	camera.current = mine
	$Body.visible = not mine
	$Head/Beak.visible = not mine
	hands = Hands.new()
	hands.name = "Hands"
	ray.add_exception(self)
	if Style.font:
		$NamePlate.font = Style.font
		$NamePlate.visible = not mine
	hands = Hands.new()
	hands.world_mode = not mine   # your own hands are first-person; everyone else's sit on the body
	(camera if mine else head).add_child(hands)
	Network.players_changed.connect(_update_nameplate)
	_update_nameplate()
	_net_pos = position
	_head_rest_y = head.position.y
	_body_rest_transform = $Body.transform
	if mine:
		overlay = Overlay.new()
		add_child(overlay)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		base_cam_rot = camera.rotation   # camera shake resets to this each frame (bug #13)
	# Wire up components.
	combat.setup(self, head, hands, overlay, state, carrier)
	combat.parry_ended.connect(_on_parry_ended)
	carrier._owner = self
	carrier.bind_registry()
	# Limp recovery: when BodyPhys limp timer expires, return to IDLE.
	body_phys.limp_recovered.connect(_on_limb_recovered)

func _update_nameplate() -> void:
	$NamePlate.text = Network.player_name(str(name).to_int())
	_apply_color()

func _apply_color() -> void:
	var c: Color = Network.player_color(str(name).to_int())
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	$Body.material_override = m
	$NamePlate.modulate = c
	if hands:
		hands.set_color(c)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Parry input must work even while parrying (F release ends the guard).
	# Everything else is blocked while parrying: no punch, interact, move, or jump.
	_parry_input(event)
	if combat.is_parrying(Time.get_ticks_msec() / 1000.0):
		return
	if overlay != null and overlay.reading:
		overlay.scroll_lore(event)
		if event.is_action_pressed("use") or event.is_action_pressed("ui_cancel"):
			overlay.close_lore()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("ui_cancel"):
		# Cancel any in-progress charge without dropping what we carry (R6: Escape
		# cancels a throw charge instead of dropping the item).
		combat.set_punch_charge_held(false, -1.0)
		carrier.charge_held = false
		carrier.charge_started = -1.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		if state.is_limp():
			_limp_yaw -= event.relative.x * MOUSE_SENS
			_limp_pitch -= event.relative.y * MOUSE_SENS
			_limp_pitch = clampf(_limp_pitch, deg_to_rad(-85), deg_to_rad(85))
		else:
			rotate_y(-event.relative.x * MOUSE_SENS)
			head.rotate_x(-event.relative.y * MOUSE_SENS)
			head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		hands.add_sway(event.relative)
	# Context resolution (one place, R6 / R1): what a press does depends on state
	# and on the kind of thing looked at - no overloaded actions.
	_carry_input(event)
	_combat_input(event)
	if event.is_action_pressed("use") and not carrier.is_carrying() and not combat.is_parrying(Time.get_ticks_msec() / 1000.0):
		_try_interact()
	# Left click presses a device (USE only - never grabs a carryable).
	# BC-1: left click presses a device when idle.
	if event.is_action_pressed("primary") and not carrier.is_carrying():
		ray.force_raycast_update()
		if ray.is_colliding():
			var target = ray.get_collider()
			var interactable := Interactable.find(target)
			while target != null and interactable == null:
				target = target.get_parent()
				if target != null:
					interactable = Interactable.find(target)
			if target != null and interactable != null and interactable.can_interact(self):
				var p := ray.get_collision_point()
				hands.reach(p)
				_net_reach.rpc(p)
				interactable.interact(self)

# --- carry input: DROP (tap Q) / THROW (hold Q); GRAB is via E (_try_interact) ----

func _carry_input(event: InputEvent) -> void:
	# Cannot do anything while being carried ourselves.
	if state.is_limp() and state.limp_phase == PlayerState.LimpPhase.LIMP_CARRIED:
		return
	# Charging / throwing (hold Q = throw charge; quick tap Q = drop).
	if carrier.is_carrying():
		if event.is_action_pressed("punch"):
			_q_press_time = Time.get_ticks_msec() / 1000.0
			carrier.start_charge()
		if event.is_action_released("punch"):
			var held := Time.get_ticks_msec() / 1000.0 - _q_press_time
			var charge := carrier.release_charge()
			if charge >= 0.0:
				if held < PhysicsTuning.TAP_MAX_SECONDS:
					# Quick tap Q = drop.
					carrier.request_drop(false)
				else:
					var dir := carrier.throw_direction()
					carrier.request_throw(dir, charge)
		return
	# Empty-handed: GRAB is handled by _try_interact on E (see above).

# --- combat input: PUNCH (charge + release), PARRY --------------------------

var _punch_input_active := false   # guards Q so a pickup doesn't also start a punch

func _combat_input(event: InputEvent) -> void:
	if carrier.is_carrying():
		return   # can't punch while carrying
	if event.is_action_pressed("punch"):
		if combat.can_start_punch_charge():
			_punch_input_active = true
			_punch_charge_auto_fired = false
			combat.set_punch_charge_held(true, Time.get_ticks_msec() / 1000.0)
	if event.is_action_released("punch"):
		if not _punch_input_active:
			return
		_punch_input_active = false
		_punch_charge_auto_fired = false
		if combat.can_release_punch_charge():
			var started := combat.punch_charge_started()
			combat.set_punch_charge_held(false, -1.0)
			var held_ms := (Time.get_ticks_msec() / 1000.0 - started) * 1000.0
			var charge := clampf(float(held_ms) / PUNCH_CHARGE_MS, 0.0, 1.0)
			if held_ms < 150:
				_combat_do_light_jab()
			else:
				_combat_throw_charged_punch(charge)

func _combat_do_light_jab() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not combat.can_do_light_jab(now):
		print("JAB: blocked by spam guard")
		return   # jab spam guard
	combat.set_last_press(now)
	# Host-authoritative: tell the host to spawn the quick-punch hitbox.
	punch_request.rpc_id(1, true, 0.0)
	if hands != null:
		hands.reach(Vector3.ZERO)

func _combat_throw_charged_punch(charge: float) -> void:
	# Host-authoritative: tell the host to spawn the charged-punch hitbox.
	var is_charged := charge >= 1.0
	print("CHARGED PUNCH: sending punch_request to host charge=%.2f" % charge)
	punch_request.rpc_id(1, false, charge)
	if charge >= 1.0:
		combat.start_lunge(-(camera.global_basis.z), LUNGE_SPEED, 0.5)
	if hands != null:
		hands.reach(Vector3.ZERO)

func _parry_input(event: InputEvent) -> void:
	if state.is_limp() or state.is_carrying():
		return   # can't parry while limp or carrying
	if event.is_action_pressed("parry"):
		var now := Time.get_ticks_msec() / 1000.0
		if combat.can_start_parry(now):
			# Start parry locally for immediate guard + input lock, then ask the host
			# to confirm and broadcast to everyone. The host's _net_parry reply is
			# authoritative and will reset the same state (harmless if already set).
			combat.start_parry(now)
			if multiplayer.is_server():
				# Host is the server: broadcast own parry directly (parry_request.rpc_id(1)
				# would target self and fail sender validation).
				_net_parry.rpc(str(name).to_int(), true)
			else:
				parry_request.rpc_id(1)
	# Press once: parry stays active for the full PARRY_GRACE_SECONDS (1.5s),
	# then auto-expires (expire_parry drops the guard). No hold-to-keep, no release-to-end.

func now_f() -> float:
	return Time.get_ticks_msec() / 1000.0

# Name of what we're holding (for the HUD inventory line).
func held_name() -> String:
	if carrier.is_carrying():
		var c: Node = carrier.carried as Node
		if c != null and c.has_method("get_interaction_prompt"):
			return c.get_interaction_prompt(self)
		return ""
	return ""

# Charge meter value 0..1 (-1 when not charging). Client UI only; host re-times
# the charge on release (R6).
func charge_meter() -> float:
	if carrier.is_carrying() and carrier.charge_started >= 0.0:
		return clampf(float((Time.get_ticks_msec() / 1000.0 - carrier.charge_started)) / Carrier.CHARGE_MS, 0.0, 1.0)
	return -1.0

# --- host-authoritative punch ----------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func punch_request(is_quick: bool, charge: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != str(name).to_int():
		return   # the requester must own the node
	if sender < -1:
		return   # invalid sender (should never happen)
	if not multiplayer.is_server():
		return   # host-authoritative: only the host spawns hitboxes
	var puncher: Player = _player_node(sender) as Player
	if puncher == null:
		# Host called locally (sender = -1 or 1): use our own player node.
		if multiplayer.is_server():
			var world := get_tree().get_first_node_in_group("game_world")
			if world != null:
				var own_id := str(name).to_int()
				puncher = world.get_node_or_null("Players/" + str(own_id)) as Player
		if puncher == null:
			return
	# Host-authoritative: host spawns the punch hitbox.
	combat.spawn_punch_hitbox(is_quick, charge, puncher, puncher.combat)
	# Notify all clients for visuals (hands reach, VFX on the puncher's node).
	var puncher_id := str(puncher.name).to_int()
	_net_punch_hitbox.rpc(puncher_id, is_quick, charge)

@rpc("any_peer", "call_local", "reliable")
func parry_request() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender < -1:
		return   # invalid sender
	if not multiplayer.is_server():
		return   # host-authoritative: only the host starts parries
	# Route to the requesting player's own combat component.
	var target_player: Node3D = _player_node(sender) as Node3D
	if target_player == null:
		# Host called locally (sender = -1 or 1): use our own player node.
		if multiplayer.is_server():
			var world := get_tree().get_first_node_in_group("game_world")
			if world != null:
				var own_id := str(name).to_int()
				target_player = world.get_node_or_null("Players/" + str(own_id)) as Node3D
		if target_player == null:
			return
	var target_combat: Combat = target_player.combat
	if not target_combat.start_parry(Time.get_ticks_msec() / 1000.0):
		return   # on cooldown or already parrying
	# Notify all clients for visuals (hands guard, barrier VFX).
	_net_parry.rpc(sender, true)
	# Host client also gets the VFX when the host is the parrier.
	if sender == str(name).to_int():
		_net_parry(sender, true)

@rpc("any_peer", "call_local", "reliable")
func parry_end_request() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != str(name).to_int():
		return   # the requester must own the node
	if sender < -1:
		return   # invalid sender
	if not multiplayer.is_server():
		return   # host-authoritative: only the host ends parries
	# Host-authoritative: host ends parry on the requesting player's combat.
	var target_player: Node3D = _player_node(sender) as Node3D
	if target_player != null:
		var target_combat: Combat = target_player.combat
		target_combat.end_parry_immediately(Time.get_ticks_msec() / 1000.0)
	# Notify all clients that parry ended.
	_net_parry.rpc(sender, false)

@rpc("any_peer", "call_remote", "unreliable")
func _net_punch_hitbox(puncher_id: int, is_quick: bool, charge: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # host-only
	var puncher_node := _player_node(puncher_id)
	var puncher: Node3D = puncher_node as Node3D
	if puncher != null and puncher.has_node("Hands"):
		var h: Hands = puncher.get_node("Hands") as Hands
		if h != null:
			h.reach(Vector3.ZERO)

			# Create hitbox on client (visual-only; host owns physics)
			var hitbox_scene: PackedScene = preload("res://player/punch_hitbox.tscn")
			var hitbox: Area3D = hitbox_scene.instantiate() as Area3D

			# Calculate position (same as host)
			var eye_pos: Vector3 = puncher.global_position + Vector3(0, 1.6, 0)
			var look_dir: Vector3 = -puncher.global_basis.z
			var range_m: float
			if is_quick:
				range_m = PhysicsTuning.QUICK_PUNCH_RANGE_M
			else:
				range_m = PhysicsTuning.CHARGED_PUNCH_RANGE_M
			var head_node: Node3D = puncher.get_node_or_null("Head") as Node3D
			hitbox.global_position = eye_pos + look_dir * (range_m * 0.5)
			hitbox.global_rotation = head_node.global_rotation if head_node != null else puncher.global_rotation

			puncher.add_child(hitbox)

@rpc("any_peer", "call_remote", "reliable")
func _net_parry(parrier_id: int, active: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var local_id := str(name).to_int()
	# Sync/clear parry combat state for the parrier on this machine. This clears
	# lingering state on the host for remote players whose grace ran out.
	var parrier_node := _player_node(parrier_id)
	if parrier_node != null:
		var parrier_player: Player = parrier_node as Player
		if parrier_player != null:
			var parrier_combat: Combat = parrier_player.combat
			if active:
				parrier_combat.set_parry_state(now + PhysicsTuning.PARRY_GRACE_SECONDS, now + PhysicsTuning.PARRY_COOLDOWN_SECONDS)
			else:
				parrier_combat.set_parry_state(0.0, now + PhysicsTuning.PARRY_COOLDOWN_SECONDS)
	# Visuals: guard/barrier on the parrier's node. Use the stored hands reference if available.
	var hands_node: Hands = null
	if parrier_node != null:
		var p: Player = parrier_node as Player
		if p != null:
			hands_node = p.hands
	if hands_node == null:
		# Fallback: try to find hands by path for remote replicas
		hands_node = parrier_node.get_node_or_null("Head/Hands") as Hands
		if hands_node == null:
			hands_node = parrier_node.get_node_or_null("Head/Camera3D/Hands") as Hands
			if hands_node == null:
				hands_node = parrier_node.get_node_or_null("Hands") as Hands
	if hands_node != null:
		hands_node.set_guard(active)
	if parrier_id == local_id:
		combat.show_remote_barrier(active)
	if overlay != null:
		overlay.notice("PARRY READY" if active else "PARRY COOLDOWN")

func _on_parry_ended() -> void:
	# The grace ran out or a parry landed. Tell everyone to drop the guard.
	# Host broadcasts directly; clients ask the host to broadcast (host is peer 1).
	var id := str(name).to_int()
	if multiplayer.is_server():
		_net_parry.rpc(id, false)
	else:
		_parry_expired_notify.rpc_id(1, id)

# Host-only: a client's parry grace expired (or the client ended parry), so tell
# everyone to drop the guard. Runs on the host because expire_parry() ticks only
# on the authority machine for remote players.
@rpc("any_peer", "call_local", "reliable")
func _parry_expired_notify(parrier_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender < -1:
		return   # invalid sender
	if not multiplayer.is_server():
		return   # only the host receives client-to-host notifications
	# Allow the parrier (or host) to notify that their parry grace expired.
	if sender != parrier_id and sender != 1:
		return   # only the player themselves (or host) may report their own expiry
	# Broadcast to every remote peer so they drop the guard for the parrier,
	# and apply it to the host's own copy of the remote parrier's state.
	_net_parry.rpc(parrier_id, false)
	_net_parry(parrier_id, false)

# Tell a puncher's client to stop their lunge immediately (host's hitbox hit someone).
# Runs on the client via authority.
@rpc("any_peer", "call_remote", "reliable")
func _net_lunge_stop() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may stop a lunge
	combat.finish_lunge()

## Every machine, every physics frame while limp: the root follows the body, never the reverse.
func _limp_puppet(delta: float) -> void:
	global_position = body_phys.global_position
	velocity = Vector3.ZERO
	_net_pos = global_position
	var mesh: Node3D = $Body
	mesh.global_basis = body_phys.global_basis                     # the tumble shows on the mesh
	mesh.global_position = body_phys.global_position + body_phys.global_basis * Vector3(0.0, 0.9, 0.0)
	if is_multiplayer_authority():
		# Anchor the camera to the tumbling body: position follows BodyPhys,
		# rotation is body tumble + accumulated mouse look.
		head.global_position = body_phys.global_position + body_phys.global_basis * Vector3(0.0, _head_rest_y, 0.0)
		head.global_basis = body_phys.global_basis * Basis(Vector3.UP, _limp_yaw) * Basis(Vector3.RIGHT, _limp_pitch)
		_net_state.rpc(global_position, rotation.y, head.rotation.x)
	else:
		# Remote viewers: head follows the tumbling body position + basis,
		# so the camera/beak/hands stay attached to the body capsule.
		head.global_position = body_phys.global_position + body_phys.global_basis * Vector3(0.0, _head_rest_y, 0.0)
		head.global_basis = body_phys.global_basis


	# Client receives a jiggle from a quick punch (visual only, no physics).
@rpc("any_peer", "call_local", "reliable")
func receive_jiggle(direction: Vector3) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # host-only
	if state.is_limp():
		return   # already down, can't jiggle
	# A light recoil bump in the punch direction (visual only, no limp).
	velocity = direction * 2.0
	show_notice("JAB")

func read_lore(title: String, text: String) -> void:
	input_locked = true
	overlay.show_lore(title, text)

func show_notice(message: String) -> void:
	if overlay != null:
		overlay.notice(message)

func _process(delta: float) -> void:
	if not is_multiplayer_authority() or overlay == null:
		return
	combat.process(delta)
	# Auto-fire charged punch when Q is held for PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS (1s).
	if _punch_input_active and not _punch_charge_auto_fired:
		var started := combat.punch_charge_started()
		if now_f() - started >= PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS:
			_punch_charge_auto_fired = true
			combat.set_punch_charge_held(false, -1.0)
			var charge := clampf(float((now_f() - started) * 1000.0) / PUNCH_CHARGE_MS, 0.0, 1.0)
			_combat_throw_charged_punch(charge)
	focus.update(ray, self, input_locked or state.is_input_locked(), Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, carrier, held_name())
	var target := focus.target
	var on := target != null
	var point := ray.get_collision_point() if on else Vector3.ZERO
	hands.set_hover(on, point)
	_highlight.set_target(target)
	# camera shake decay
	var t := Time.get_ticks_msec() / 1000.0
	if t < _cam_shake_until:
		var s := _cam_shake_intensity * 0.03
		camera.rotation.x = base_cam_rot.x + randf_range(-s, s)
		camera.rotation.y = base_cam_rot.y + randf_range(-s, s)
	else:
		_cam_shake_until = 0.0
		camera.rotation.x = base_cam_rot.x
		camera.rotation.y = base_cam_rot.y
	overlay.update_focus(focus.prompt, held_name(), charge_meter(), focus.active)

	# Sync hover/point state to other players only when it changes.
	var hover_on := focus.target != null
	var hover_point := ray.get_collision_point() if hover_on else Vector3.ZERO
	if hover_on != _hover_on or not hover_point.is_equal_approx(_hover_point):
		_hover_on = hover_on
		_hover_point = hover_point
		_net_hover_state.rpc(hover_on, hover_point)

func _exit_tree() -> void:
	_highlight.clear()

func _try_interact() -> void:
	if carrier.is_carrying():
		return   # can't interact while carrying something
	if state.is_limp():
		return   # limp players can't interact
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var target = ray.get_collider()
	var interactable := Interactable.find(target)
	while target != null and interactable == null:
		target = target.get_parent()
		if target != null:
			interactable = Interactable.find(target)
	if target != null and interactable != null and interactable.can_interact(self):
		# Healthy players are not GRAB targets; only limp/carried ones are.
		if str(target.name).match(r"^\d+$"):
			var t: Variant = target
			if t.has_method("is_limp") and not t.is_limp():
				return
		var p := ray.get_collision_point()
		hands.reach(p)
		_net_reach.rpc(p)
		interactable.interact(self)

func _player_node(id: int) -> Node:
	var world := get_tree().get_first_node_in_group("game_world")
	return world.get_node_or_null("Players/" + str(id)) if world != null else null

# --- limp-player Carryable interface (when THIS player is carried) ----------

# Called by Carrier / CarryRegistry when this player is picked up as a carried body.
# NO reparenting (it breaks Players/<id> and every RPC path). NO mouse release: a
# carried player can still look around in front of the carrier. The limp timer is
# paused by BodyPhys while carried.
func pickup(holder: Node) -> void:
	state.set_limp_phase(PlayerState.LimpPhase.LIMP_CARRIED)
	body_phys.set_carry_mode(holder as Node3D, get_carry_offset())

# Called by Carrier on drop or throw. BodyPhys restarts the limp timer
# (LIMP_SECONDS) so they stay down after being put down or thrown.
func release(throw: bool, direction: Vector3, speed: float) -> void:
	state.set_limp_phase(PlayerState.LimpPhase.LIMP_THROWN if throw else PlayerState.LimpPhase.LIMP_GROUND)
	body_phys.clear_carry_mode(direction.normalized() * speed if throw else Vector3.ZERO)


func is_carried() -> bool:
	return state.is_limp() and state.limp_phase == PlayerState.LimpPhase.LIMP_CARRIED

# True while this player is limp (knocked down / carried / thrown).
func is_limp() -> bool:
	return state.is_limp()

func get_carry_offset() -> Vector3:
	return Vector3(0.0, 0.2, -1.0)

func get_throw_speed(charge: float) -> float:
	return lerpf(6.0, 16.0, clampf(charge, 0.0, 1.0))

# Called by another player looking at this limp player. Host applies via CarryRegistry.
func interact(player: Node) -> void:
	if not state.is_limp():
		return  # not limp, can't be picked up
	if state.limp_phase == PlayerState.LimpPhase.LIMP_CARRIED:
		return  # already being carried
	var carrier_id := str(player.name).to_int()
	if carrier_id == 0:
		carrier_id = 1
	var carrier_node := _player_node(carrier_id)
	if carrier_node == null or carrier_node.carrier.is_carrying():
		return
	CarryRegistry.hold_request_pickup.rpc_id(1, carrier_id, name)

# --- physics process ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if state.is_limp():
		_limp_puppet(delta)
		return
	if not is_multiplayer_authority():
		# Remote copy: interpolate toward the owner's authoritative state.
		position = position.lerp(_net_pos, 0.3)
		rotation.y = lerp_angle(rotation.y, _net_yaw, 0.3)
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, 0.3)
		return
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not (input_locked or state.is_input_locked() or combat.is_parrying(now)):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	# Preserve charged-punch lunge velocity during flight: input can't overwrite x/z.
	if combat.is_lunging(now):
		# Camera-arced lunge: steer toward where the player is looking while lunging,
		# so they can arc left/right by looking that direction during the lunge.
		combat.steer_lunge(-(camera.global_basis.z), 1.0, 10.0, delta)
		velocity.x = combat.lunge_velocity().x
		velocity.z = combat.lunge_velocity().z
	elif combat.is_parrying(now):
		velocity.x = 0.0   # parry stance = standing still (otherwise you slide on old velocity)
		velocity.z = 0.0
	elif not (input_locked or state.is_input_locked() or combat.is_parrying(now)) and now >= (state.limp_timer if state.limp_timer > 0.0 else 0.0):
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	move_and_slide()
	if Time.get_ticks_msec() - _last_push > 0.18:
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			if collider is PhysicsProp:
				collider.request_push.rpc_id(1)   # host-validated push via CarryRegistry
				_last_push = Time.get_ticks_msec() / 1000.0
				break
	hands.set_speed(Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0)
	_net_state.rpc(position, rotation.y, head.rotation.x)
	_apply_jiggle(delta)
	if velocity.length() > 8.0 and not is_on_floor():
		var wall_hit := false
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			if collider is not PhysicsProp and collider is not CharacterBody3D:
				wall_hit = true
				break
		if wall_hit and Time.get_ticks_msec() / 1000.0 > _wall_hit_until:
			_wall_hit_until = Time.get_ticks_msec() / 1000.0 + 0.3
			_wall_hit_vfx.rpc(velocity.length())

# Jiggle spring: visual wobble that recoils then returns (jelly body response).
func _apply_jiggle(delta: float) -> void:
	if _jiggle_velocity.length() < 0.01:
		_jiggle_velocity = Vector3.ZERO
		return
	_jiggle_velocity -= _jiggle_offset * JIGGLE_STIFFNESS * delta
	_jiggle_velocity *= 1.0 - JIGGLE_DAMPING * delta
	_jiggle_offset += _jiggle_velocity * delta
	if $Body != null:
		$Body.position = _jiggle_offset

@rpc("any_peer", "call_local", "reliable")
func _wall_hit_vfx(speed: float) -> void:
	var intensity := clampf(speed / 20.0, 0.5, 1.5)
	show_notice("WALL SLAM!")
	if hands != null:
		hands.shake(intensity)
	_cam_shake_until = Time.get_ticks_msec() / 1000.0 + 0.25
	_cam_shake_intensity = intensity

@rpc("authority", "call_remote", "unreliable")
func _net_state(pos: Vector3, yaw: float, pitch: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch

@rpc("authority", "call_remote", "unreliable")
func _net_hover_state(on: bool, point: Vector3) -> void:
	hands.set_hover(on, point)

@rpc("authority", "call_remote", "unreliable")
func _net_hover_point(point: Vector3) -> void:
	hands.update_hover_point(point)

@rpc("authority", "call_remote", "unreliable")
func _net_reach(point: Vector3) -> void:
	hands.reach(point)

@rpc("any_peer", "call_local", "reliable")
func teleport_to(pos: Vector3, yaw: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may move players
	position = pos
	CarryRegistry.on_teleport(str(name).to_int())   # drop what we carry
	carrier.charge_started = -1.0
	carrier.charge_held = false
	if overlay != null:
		overlay.close_lore()
	rotation.y = yaw
	_net_yaw = yaw
	velocity = Vector3.ZERO
	_net_pos = pos
