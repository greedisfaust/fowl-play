extends CharacterBody3D

## Player node: thin coordinator.
## Input → component calls (Focus / Combat / Carrier / PlayerState), RPCs, node mutation.
## All carry/combat state lives in the components — no loose `_carrier_id` /
## `_carried_player_id` / `_knocked_down_until` vars here.

const SPEED := 5.0
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.003

const Interactable := preload("res://interaction/interactable.gd")
const PhysicsProp := preload("res://interaction/physics_prop.gd")
const Overlay := preload("res://ui/interaction_overlay.gd")

# Re-exported for tests and callers that still reference them directly.
const PUNCH_CHARGE_MS := 500      # hold Q this long for a charged punch
const PARRY_COOLDOWN := 1.5       # seconds before F can parry again
const PARRY_GRACE := 1.5          # max seconds parry stays active while holding F
const PUNCH_RANGE := 3.0          # how far a charged punch reaches (bug #9)
const LUNGE_SPEED := 12.0         # how far a charged punch lunges the puncher

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/RayCast3D

# --- network / interpolation state ---
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var input_locked := false
var hands: Hands
var overlay: InteractionOverlay
var _last_push := 0
var _hover_on := false
var _hover_point := Vector3.ZERO

# --- components ---
var state: PlayerState = PlayerState.new()   # explicit player state machine
var focus: Focus = Focus.new()               # local "what am I looking at"
var combat: Combat = Combat.new()            # punch / parry / knockdown / ragdoll
var carrier: Carrier = Carrier.new()         # single code path for item + downed-player carry
var _highlight: FocusHighlight = FocusHighlight.new()   # glow/outline on hovered target
var base_cam_rot: Vector3 = Vector3.ZERO     # base camera rotation (shaking resets to this each frame)

# --- jiggle spring (visual only: mesh lags behind body, then snaps back) ---
var _jiggle_offset := Vector3.ZERO
var _jiggle_velocity := Vector3.ZERO
const JIGGLE_STIFFNESS := 14.0
const JIGGLE_DAMPING := 0.6

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	var mine := is_multiplayer_authority()
	camera.current = mine
	$Body.visible = not mine
	$Head/Beak.visible = not mine
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
	if mine:
		overlay = Overlay.new()
		add_child(overlay)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		base_cam_rot = camera.rotation   # camera shake resets to this each frame (bug #13)
	# Wire up components.
	combat.setup(self, head, ray, hands, overlay, state, carrier)
	carrier.owner = self

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
	if overlay != null and overlay.reading:
		overlay.scroll_lore(event)
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			overlay.close_lore()
			input_locked = false
		get_viewport().set_input_as_handled()
		return
	if input_locked:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel_charge()
		combat.set_punch_charge_held(false, -1.0)
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		hands.add_sway(event.relative)
	_handle_carry_input(event)
	_combat_input(event)
	_combat_parry_input(event)
	# Only interact when not carrying anything — fixes the button bug while holding an item/player
	if not carrier.is_carrying():
		if event.is_action_pressed("interact") or event.is_action_pressed("primary"):
			_try_interact()

func _resolve_carry_state() -> void:
	# Safety: if our Carrier reference is gone (freed prop, disconnect),
	# clear it so G-drop and Q-throw work again instead of leaving you stuck.
	if carrier.carried != null and not is_instance_valid(carrier.carried):
		carrier.drop(false)

func is_stunned() -> bool:
	return state.is_knocked_down() or state.is_ragdolled() or state.is_carried()

# --- carry input (G drop, Q throw, Q pickup) ---

func _handle_carry_input(event: InputEvent) -> void:
	# Cannot do anything while being carried ourselves.
	if state.is_carried():
		return
	# Dropping what we carry (G).
	if event.is_action_pressed("drop_item"):
		if carrier.is_carrying():
			var c: Node = carrier.carried as Node
			if c is PhysicsProp and c.holder_id != 0:
				# item: server-mediated release (drop, no throw)
				c.request_release.rpc_id(1, false)
			carrier.drop(false)
		return
	# Charging / throwing (hold Q or RMB, release).
	if carrier.is_carrying():
		if event.is_action_pressed("throw_item") or event.is_action_pressed("punch_charge"):
			carrier.start_charge()
			var c: Node = carrier.carried as Node
			if c is PhysicsProp:
				c.request_charge.rpc_id(1)   # set prop's charge start so request_release(true) isn't rejected
		if event.is_action_released("throw_item") or event.is_action_released("punch_charge"):
			var charge := carrier.release_charge()
			if charge >= 0.0:
				_apply_carry_throw(charge)
		return
	# Empty-handed: Q picks up looked-at target (item or downed player).
	if event.is_action_pressed("punch_charge"):
		var target := ray.get_collider() if ray.is_colliding() else null
		# Raycasts hit body parts — walk up to find the player root.
		while target != null and not target.name.match(r"^\d+$"):
			target = target.get_parent()
		if target != null and Interactable.can(target):
			# Only downed/stunned players can be picked up — never healthy ones.
			var t: Variant = target
			if t.is_stunned():
				carrier.pickup(target)
		# One-frame guard so a pickup doesn't also start a punch charge.
		pass

# Single throw path for item or downed player, replicated appropriately.
func _apply_carry_throw(charge: float) -> void:
	if not carrier.is_carrying():
		return
	var c: Node = carrier.carried as Node
	var direction: Vector3 = -get_node("Head").global_basis.z
	if c is PhysicsProp:
		# item: server-mediated throw via request_release (server applies
		# direction from holder's head + speed from its own charge timing).
		c.request_release.rpc_id(1, true)
	else:
		# downed / ragdolled player: launch RPC targeting the carried player.
		# c.name is set to the carried player's peer ID at spawn (world.gd).
		var carried_id := str(c.name).to_int()
		if carried_id != 0:
			var speed := lerpf(6.0, 16.0, charge)
			_launch_carried_player.rpc_id(carried_id, direction, speed, carried_id)
	carrier.drop(true)

# --- combat input (punch / jab / parry) ---

func _combat_input(event: InputEvent) -> void:
	# Q starts / releases a punch charge only when empty-handed (no item, no carried player).
	if carrier.is_carrying():
		return
	if event.is_action_pressed("punch_charge"):
		_combat_start_punch_charge()
	if event.is_action_released("punch_charge"):
		_combat_release_punch_charge()

func _combat_start_punch_charge() -> void:
	if not combat.can_start_punch_charge():
		return
	combat.set_punch_charge_held(true, Time.get_ticks_msec() / 1000.0)

func _combat_release_punch_charge() -> void:
	if not combat.can_release_punch_charge():
		return
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
		return   # jab spam guard
	combat.set_last_press(now)
	var target := combat.raycast_hit()
	if target != null:
		var target_peer := _peer_of_node(target)
		if target_peer != 0:
			# Host-authoritative: ask the host to validate and apply the punch.
			punch_request.rpc_id(1, target_peer, 0.0)
	# Everyone else sees our hand swing; we see it locally.
	_net_jab.rpc()
	if hands != null:
		var p := ray.get_collision_point() if ray.is_colliding() else Vector3.ZERO
		hands.reach(p)

func _combat_throw_charged_punch(charge: float) -> void:
	var target := combat.raycast_hit()
	if target != null:
		var target_peer := _peer_of_node(target)
		if target_peer != 0:
			var is_charged := charge >= 1.0
			punch_request.rpc_id(1, target_peer, charge)
	# Lunge the puncher forward on a charged punch.
	if charge >= 1.0:
		combat.lunge(LUNGE_SPEED)
	_net_punch.rpc(charge)
	if hands != null:
		var p := ray.get_collision_point() if ray.is_colliding() else Vector3.ZERO
		hands.reach(p)

func _combat_parry_input(event: InputEvent) -> void:
	if state.is_knocked_down() or state.is_ragdolled() or state.is_carrying():
		return   # can't parry while down, ragdolled, or carrying
	if event.is_action_pressed("parry"):
		var now := Time.get_ticks_msec() / 1000.0
		if combat.can_start_parry(now):
			combat.start_parry(now)
			hands.set_guard(true)
	if event.is_action_released("parry"):
		hands.set_guard(false)

func now_f() -> float:
	return Time.get_ticks_msec() / 1000.0

# Name of what we're holding (for the HUD inventory line).
func held_name() -> String:
	if carrier.is_carrying():
		var c: Node = carrier.carried as Node
		if c != null:
			return c.get_interaction_prompt(self)
		return ""
	return ""

# Charge meter value 0..1 (-1 when not charging).
func charge_meter() -> float:
	if carrier.is_carrying() and carrier.charge_started >= 0.0:
		return clampf(float(Time.get_ticks_msec() - carrier.charge_started) / Carrier.CHARGE_MS, 0.0, 1.0)
	return -1.0

# Find the peer id of a node by walking up to the Players/<id> ancestor.
func _peer_of_node(node: Node) -> int:
	var n: Node = node
	while n != null:
		if n.name.match(r"^\d+$"):
			return n.name.to_int()
		n = n.get_parent()
	return 0

# Host-authoritative punch request. Client asks the host to validate + apply a punch.
@rpc("any_peer", "call_local", "reliable")
func punch_request(target_id: int, charge: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may process punch requests
	var puncher := _player_node(sender)
	var target := _player_node(target_id)
	if puncher == null or target == null:
		return
	# Validate reach + state (bug #9: PUNCH_RANGE enforced here).
	var result := combat.validate_punch(puncher, target, charge)
	var valid := bool(result[0])
	var is_charged := bool(result[1])
	if not valid:
		return
	# Tell the target to take the punch (authority RPC: only host can trigger it).
	take_punch.rpc_id(target_id, sender, charge, is_charged)

@rpc("authority", "call_local", "reliable")
func take_punch(attacker_id: int, _charge: float, is_charged: bool) -> void:
	# Only the host may trigger punches (bug #8 fix: no client-side knock-down cheat).
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return

	# If the target is parrying, the attacker gets ragdolled back instead.
	if combat.is_parrying(now_f()):
		combat.expire_parry(now_f())
		var attacker := _player_node(int(attacker_id))
		if attacker != null:
			var attacker_hands := attacker.get_node_or_null("Hands")
			if attacker_hands != null:
				attacker_hands.set_guard(false)
			# Parry reflect: ragdoll the attacker away from the defender.
			var direction := (attacker.global_position - global_position).normalized()
			if direction == Vector3.ZERO:
				direction = -get_node("Head").global_basis.z
			attacker.apply_ragdoll(direction, 10.0, 2.5)
		show_notice("PARRIED!")
		return

	if is_charged:
		# Charged punch: ragdoll the target, sent flying away from the attacker.
		var attacker := _player_node(int(attacker_id))
		var from: Vector3 = attacker.global_position if attacker != null else global_position - get_node("Head").global_basis.z
		var direction: Vector3 = (global_position - from).normalized()
		combat.apply_ragdoll(direction, 14.0, 2.5)
		# Shakedown: only during Day phase (casino), never in lobby/rest
		if GameState.phase == GameState.Phase.DAY:
			var pct := 5
			var new_wallet := maxi(0, GameState.wallet - (GameState.wallet * pct / 100.0))
			GameState._set_wallet.rpc(new_wallet)   # host-authoritative, replicates to all
			show_notice("SHAKEDOWN - %d%%" % pct)
		else:
			show_notice("KNOCKED DOWN")
	else:
		# Light jab: brief flinch, jiggle recoil (jelly body response), no knockdown.
		state.ragdolled_until = Time.get_ticks_msec() / 1000.0 + 0.35
		input_locked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Jiggle recoil: body recoils backwards from the punch then returns.
		var attacker := _player_node(int(attacker_id))
		if attacker != null:
			var dir := (global_position - attacker.global_position).normalized()
			_jiggle_velocity = dir * 2.0   # jelly recoil
		show_notice("JAB")

func _cancel_charge() -> void:
	if carrier.is_carrying():
		carrier.drop(false)

# Apply ragdoll to this player (called by Combat on the host, or by take_punch).
func apply_ragdoll(direction: Vector3, speed: float, seconds: float) -> void:
	combat.apply_ragdoll(direction, speed, seconds)

func read_lore(title: String, text: String) -> void:
	_cancel_charge()
	input_locked = true
	overlay.show_lore(title, text)

func show_notice(message: String) -> void:
	if overlay != null:
		overlay.notice(message)

func _process(delta: float) -> void:
	if not is_multiplayer_authority() or overlay == null:
		return
	combat.process(delta)   # expire parry grace -> cooldown
	# Knockdown expired naturally: restore movement and release carrier link
	# But NOT while being carried — carried players stay down until thrown.
	var now := now_f()
	if state.ragdolled_until > 0.0 and not state.is_carried() and now >= state.ragdolled_until:
		state.ragdolled_until = 0.0
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	focus.update(ray, self, input_locked, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, carrier, held_name())
	var target := focus.target
	var on := target != null
	var point := ray.get_collision_point() if on else Vector3.ZERO
	hands.set_hover(on, point)
	_highlight.set_target(target)
	# camera shake decay — reset to base rotation each frame so it never drifts (bug #13)
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
	if not ray.is_colliding():
		return
	var target = ray.get_collider()
	# Raycasts hit body parts — walk up to find the interactable target
	# (player roots implement Interactable via interact()/get_interaction_prompt()).
	while target != null and not Interactable.can(target):
		target = target.get_parent()
	if target and Interactable.can(target):
		# Healthy players are NOT interactable — only downed/stunned/carried ones.
		# Player.interact() enforces this, but we guard here so we don't even
		# trigger the reach RPC or hand swing on a healthy player.
		if target.name.match(r"^\d+$"):
			var t: Variant = target
			if not t.is_stunned():
				return
		var p := ray.get_collision_point()
		hands.reach(p)
		_net_reach.rpc(p)   # tell everyone else where to swing this player's hand
		target.interact(self)

func _player_node(id: int) -> Node3D:
	var world := get_tree().get_first_node_in_group("game_world")
	return world.get_node_or_null("Players/" + str(id)) if world != null else null

@rpc("authority", "call_remote", "unreliable")
func _net_jab() -> void:
	hands.reach(ray.get_collision_point())

@rpc("authority", "call_remote", "unreliable")
func _net_punch(_charge: float) -> void:
	hands.reach(ray.get_collision_point())

# Called by physics_prop when this player picks up or drops an item.
# Delegates to Carrier (single carry path).
func _set_carry_item(item: PhysicsProp) -> void:
	carrier.pickup(item)

func _clear_carry_item() -> void:
	carrier.drop(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func get_interaction_prompt(_player: Node) -> String:
	if state.is_ragdolled() or state.is_knocked_down():
		return "Pick up"
	return "Interact"

# --- carry / throw knocked-down / ragdolled players (Carryable interface) ---

# Called by Carrier when this player is picked up as a carried body.
func pickup(holder: Node) -> void:
	state.transition_to(PlayerState.State.CARRIED)
	input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	head.rotation.x = deg_to_rad(60)
	# Detach from world so the carrier can move us.
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	holder.add_child(self)

# Called by Carrier on drop or throw.
func release(throw: bool, direction: Vector3, speed: float) -> void:
	if throw:
		velocity = direction * speed
		state.transition_to(PlayerState.State.THROWN)
		state.ragdolled_until = Time.get_ticks_msec() / 1000.0 + 2.5
		head.rotation.x = deg_to_rad(60)
		# Detach from carrier before re-adding to world.
		var parent := get_parent()
		if parent != null:
			parent.remove_child(self)
		var world = get_tree().get_first_node_in_group("game_world")
		if world != null:
			world.add_child(self)
	else:
		# Drop back to the world.
		state.transition_to(PlayerState.State.IDLE)
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		head.rotation.x = 0.0
		var parent := get_parent()
		if parent != null:
			parent.remove_child(self)
		var world = get_tree().get_first_node_in_group("game_world")
		if world != null:
			world.add_child(self)

func is_carried() -> bool:
	return state.is_carried()

func get_carry_offset() -> Vector3:
	# Both-hands offset for carried players: lower, centered in front of carrier.
	return Vector3(0.0, 0.2, -1.0)

func get_throw_speed(charge: float) -> float:
	return lerpf(6.0, 16.0, clampf(charge, 0.0, 1.0))

# Called by another player pressing Q while looking at this downed/ragdolled player.
# Runs on all machines; the RPC sets CARRYING/CARRIED state on each owner's machine.
func interact(player: Node) -> void:
	if not (state.is_knocked_down() or state.is_ragdolled()):
		return  # not downed, can't be picked up
	if state.is_carried():
		return  # already being carried
	var carrier_id := str(player.name).to_int()
	if carrier_id == 0:
		carrier_id = 1
	var carrier_node := _player_node(carrier_id)
	if carrier_node == null or carrier_node.carrier.is_carrying():
		return  # carrier already holding someone
	var carried_id := str(name).to_int()
	if carried_id == 0:
		carried_id = 1
	_pickup_request.rpc(carrier_id, carried_id)

@rpc("any_peer", "call_local", "reliable")
func _pickup_request(carrier_id: int, carried_id: int) -> void:
	# Runs on all machines. Each machine sets state for the player it owns.
	var my_id := multiplayer.get_unique_id()
	if my_id == carrier_id:
		var carrier_node := _player_node(carrier_id)
		if carrier_node != null:
			carrier_node.state.transition_to(PlayerState.State.CARRYING)
	elif my_id == carried_id:
		state.transition_to(PlayerState.State.CARRIED)
		_carrier_id = carrier_id
		input_locked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		head.rotation.x = deg_to_rad(60)

# Spring/lerp follow for carried players (replaces the old _carry_tick snap).
# Runs on the carried player's machine each physics frame.
func _carry_follow(delta: float) -> void:
	if not state.is_carried() or _carrier_id == 0:
		return
	var carrier := _player_node(_carrier_id)
	if carrier == null:
		return
	var offset := carrier.global_basis * get_carry_offset()
	var target := carrier.global_position + offset
	# Raycast from carrier to target: stop at walls so carried player doesn't clip.
	var from := carrier.global_position
	var query := PhysicsRayQueryParameters3D.create(from, target)
	query.exclude = [carrier.get_rid(), get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.position + hit.normal * 0.25
	# Spring toward target (soft, not robotic).
	global_position = global_position.lerp(target, minf(delta * 10.0, 1.0))
	global_basis = carrier.global_basis

# Ragdoll physics: tumble while flying, slide to a stop, recover when slow.
func _ragdoll_physics(delta: float) -> void:
	if not state.is_ragdolled() and not state.is_knocked_down():
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	# Tumble visual: rotate the head over time for a limp look.
	head.rotation.x += delta * 2.0
	head.rotation.z += delta * 1.5
	move_and_slide()
	# Recover when speed drops below threshold or ragdoll time expired.
	var now := now_f()
	if velocity.length() < 0.5 or (state.ragdolled_until > 0.0 and now >= state.ragdolled_until):
		state.ragdolled_until = 0.0
		state.transition_to(PlayerState.State.IDLE)
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		head.rotation.x = 0.0
		head.rotation.z = 0.0
		velocity = Vector3.ZERO

# Jiggle spring: visual wobble that recoils then returns (jelly body response).
func _apply_jiggle(delta: float) -> void:
	if _jiggle_velocity.length() < 0.01:
		_jiggle_velocity = Vector3.ZERO
		return
	# Spring toward zero (original state).
	_jiggle_velocity -= _jiggle_offset * JIGGLE_STIFFNESS * delta
	_jiggle_velocity *= 1.0 - JIGGLE_DAMPING * delta
	_jiggle_offset += _jiggle_velocity * delta
	# Apply as a visual offset to the body mesh (not collision).
	if $Body != null:
		$Body.position = _jiggle_offset

@rpc("any_peer", "call_local", "reliable")
func _launch_carried_player(direction: Vector3, speed: float, target_id: int) -> void:
	# Runs on the carried player's machine: release with launch velocity.
	var my_id := multiplayer.get_unique_id()
	if my_id != target_id:
		return
	_carrier_id = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	velocity = direction * speed
	state.ragdolled_until = Time.get_ticks_msec() / 1000.0 + 2.5
	head.rotation.x = deg_to_rad(60)
	var world = get_tree().get_first_node_in_group("game_world")
	if world != null:
		world.add_child(self)

@rpc("authority", "call_local", "reliable")
func teleport_to(pos: Vector3, yaw: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may move players
	position = pos
	carrier.drop(false)   # bug #11: teleporting must not let you keep carried items/players
	_cancel_charge()
	if overlay != null:
		overlay.close_lore()
		input_locked = false
	rotation.y = yaw
	_net_yaw = yaw
	velocity = Vector3.ZERO
	_net_pos = pos

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		position = position.lerp(_net_pos, 0.3)
		rotation.y = lerp_angle(rotation.y, _net_yaw, 0.3)
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, 0.3)
		return
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not input_locked:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	# Preserve throw velocity during launch flight; don't overwrite it with input
	var now := Time.get_ticks_msec() / 1000.0
	if not input_locked and now >= (state.ragdolled_until if state.ragdolled_until > 0.0 else 0.0):
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	if state.is_carried():
		_carry_follow(delta)   # being carried: follow carrier with spring
	elif state.is_ragdolled() or state.is_knocked_down():
		_ragdoll_physics(delta)   # tumbling physics
	else:
		move_and_slide()
	if Time.get_ticks_msec() - _last_push > 180:
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			if collider is PhysicsProp:
				collider.request_push.rpc_id(1)
				_last_push = Time.get_ticks_msec()
				break
	hands.set_speed(Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0)
	_net_state.rpc(position, rotation.y, head.rotation.x)
	# Apply jiggle spring (visual only).
	_apply_jiggle(delta)
	# wall-hit VFX: if we're moving fast and collide with a wall, play impact
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

@rpc("any_peer", "call_local", "reliable")
func _wall_hit_vfx(speed: float) -> void:
	var intensity := clampf(speed / 20.0, 0.5, 1.5)
	show_notice("WALL SLAM!")
	if hands != null:
		hands.shake(intensity)
	# camera shake (this peer's own camera) — applied in _process below
	_cam_shake_until = Time.get_ticks_msec() / 1000.0 + 0.25
	_cam_shake_intensity = intensity

@rpc("authority", "call_remote", "unreliable")
func _net_state(pos: Vector3, yaw: float, pitch: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch

@rpc("authority", "call_remote", "reliable")
func _net_hover_state(on: bool, point: Vector3) -> void:
	hands.set_hover(on, point)

@rpc("authority", "call_remote", "unreliable")
func _net_hover_point(point: Vector3) -> void:
	hands.update_hover_point(point)

@rpc("authority", "call_remote", "reliable")
func _net_reach(point: Vector3) -> void:
	hands.reach(point)   # runs on everyone else's copy of this player

# Legacy vars kept for test compatibility during transition.
var _charge_started := -1
var _knocked_down_until := 0.0
var _carrier_id := 0
var _carried_player_id := 0
var _pickup_attempting := false
var _just_picked_up := false
var _wall_hit_until := 0.0          # time until wall-hit stun expires
var _cam_shake_until := 0.0         # time until camera shake expires
var _cam_shake_intensity := 1.0
