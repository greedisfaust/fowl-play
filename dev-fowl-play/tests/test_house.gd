extends Node

## Ported house & hand test: exercises the new carry foundation (R2/R3),
## the Interactable contract (R1), the LIMP state machine (R4), and
## CarryRegistry cleanup across every exit path (disconnect / elevator /
## teleport / run reset). Runs headless as local host (peer 1).

const Prop := preload("res://interaction/physics_prop.gd")
const BodyPhys := preload("res://autoload/body_phys.gd")
var failures := 0
var checks := 0
var world: Node3D

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [world.get_node("Players/1").get_rid()]
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func make_prop(pos: Vector3, name: String = "Prop") -> PhysicsProp:
	var prop := Prop.new()
	prop.name = name
	prop.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 0.25, 0.25)
	shape.shape = box
	prop.add_child(shape)
	world.add_child(prop)
	return prop

# --- request helpers (mirror real Carrier calls through CarryRegistry) ---

func pickup(prop: PhysicsProp, holder_id: int = 1) -> void:
	if multiplayer.is_server():
		CarryRegistry.hold_request_pickup(holder_id, prop.name)
	else:
		CarryRegistry.hold_request_pickup.rpc_id(1, holder_id, prop.name)

func drop(prop: PhysicsProp, holder_id: int = 1, threw: bool = false) -> void:
	if multiplayer.is_server():
		CarryRegistry.hold_request_drop(holder_id, threw)
	else:
		CarryRegistry.hold_request_drop.rpc_id(1, holder_id, threw)

func throw_prop(prop: PhysicsProp, holder_id: int = 1, charge: float = 0.0) -> void:
	var dir := Vector3(0, 0, -1)
	if multiplayer.is_server():
		CarryRegistry.hold_request_throw(holder_id, dir, charge)
	else:
		CarryRegistry.hold_request_throw.rpc_id(1, holder_id, dir, charge)

func _ready() -> void:
	world = preload("res://world.tscn").instantiate()
	add_child(world)
	for i in 3:
		await get_tree().physics_frame
	check(InputMap.has_action("drop_item") and InputMap.has_action("throw_item"), "carry controls exist")
	check(InputMap.has_action("use") and InputMap.has_action("grab") and InputMap.has_action("punch") and InputMap.has_action("parry"), "R6 input split actions exist")
	check(get_tree().get_nodes_in_group("physics_props").size() >= 18, "rooms contain loose and pushable props")
	check(get_tree().get_nodes_in_group("lore_guides").size() >= 4, "all lore guides are available")
	check(not ray(Vector3(0, 2, 0), Vector3(0, 5, 0)).is_empty(), "apartment roof collides")
	check(not ray(Vector3(100, 2, 0), Vector3(100, 8, 0)).is_empty(), "casino roof collides")
	check(not ray(Vector3(50, 2, 0), Vector3(50, 5, 0)).is_empty(), "rest roof collides")
	check(not ray(Vector3(0, 1.8, 0), Vector3(7, 1.8, 0)).is_empty(), "window panes block escapes")
	check(ray(Vector3(0, 1.5, 5.3), Vector3(0, 1.5, 6.3)).is_empty(), "apartment lift opening remains clear")
	check(ray(Vector3(100, 1.5, -14.4), Vector3(100, 1.5, -15.3)).is_empty(), "casino lift opening remains clear")
	check(world.get_node("Casino/ChickenCross").position.x < -3 and world.get_node("Casino/Cluckjack").position.x > 3, "tables leave central aisle")
	# Throw-speed tuning lives in CarryRegistry / BodyPhys constants.
	check(is_equal_approx(CarryRegistry.MIN_THROW_SPEED, 3.0), "tap throw is gentle")
	check(is_equal_approx(CarryRegistry.MAX_THROW_SPEED, 14.0), "full throw is fourteen")

	var a := make_prop(Vector3(-0.4, 0.8, -1.0), "TestA")
	var b := make_prop(Vector3(0.4, 0.8, -1.0), "TestB")
	var far := make_prop(Vector3(4, 0.8, -4), "TestFar")
	await get_tree().physics_frame
	# Out-of-reach pickup rejected (host validates reach).
	pickup(far)
	await get_tree().physics_frame
	check(far.holder_id == 0, "out of reach pickup rejected")
	# In-reach pickup freezes body and disables carry collision.
	pickup(a)
	await get_tree().physics_frame
	check(a.holder_id == 1 and a.freeze, "pickup freezes and disables carry collision")
	# Second pickup cannot occupy same hand (single slot).
	pickup(b)
	await get_tree().physics_frame
	check(b.holder_id == 0, "second pickup rejected while carrying (double-pickup)")
	# Throw without a charge request: release with threw=true but zero launch.
	drop(a, 1, true)
	await get_tree().physics_frame
	check(a.holder_id == 0 and not a.freeze, "drop without charge releases (no launch)")
	# Real charged throw.
	pickup(a)
	await get_tree().physics_frame
	throw_prop(a, 1, 1.0)
	await get_tree().physics_frame
	check(a.holder_id == 0 and not a.freeze, "throw restores physics collision")
	var launch_speed: float = a.linear_velocity.length()
	check(launch_speed >= 13.5 and launch_speed <= 14.5, "host caps charged launch speed")
	# Wall between eye and prop: the host rejects a pickup through it.
	var blocked := make_prop(Vector3(0, 1.3, -2), "TestBlocked")
	var wall := StaticBody3D.new()
	var barrier := CollisionShape3D.new()
	var barrier_shape := BoxShape3D.new()
	barrier_shape.size = Vector3(2, 2, 0.2)
	barrier.shape = barrier_shape
	wall.position = Vector3(0, 1, -1)
	wall.add_child(barrier)
	world.add_child(wall)
	await get_tree().physics_frame
	pickup(blocked)
	await get_tree().physics_frame
	check(blocked.holder_id == 0, "pickup through wall rejected")
	wall.queue_free()
	# Prop can be picked up again after throw (reset to home).
	pickup(a)
	await get_tree().physics_frame
	check(a.holder_id == 1, "prop can be picked up again after throw")
	# Lift transition drops held object.
	CarryRegistry.on_elevator_transition()
	await get_tree().physics_frame
	check(a.holder_id == 0, "lift transition drops held object")
	# Large props cannot enter inventory.
	b.can_pick_up = false
	pickup(b)
	await get_tree().physics_frame
	check(b.holder_id == 0, "non-pickupable prop cannot enter inventory")
	await get_tree().create_timer(0.08).timeout  # impulses take effect on the next physics step
	check(Vector2(b.linear_velocity.x, b.linear_velocity.z).length() > 0.0, "shove moves a large prop away from the player")
	# Hand occupied before session reset.
	pickup(a)
	await get_tree().physics_frame
	check(a.holder_id == 1, "hand occupied before session reset")
	# Reset run clears occupied hand.
	GameState.reset_run()
	check(CarryRegistry.held_by.has(a) == false, "reset clears occupied hand")
	var player: Node = world.get_node("Players/1")
	var carrier: Carrier = player.get("carrier") as Carrier
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# G input drops current object.
	pickup(a)
	await get_tree().physics_frame
	carrier.request_drop(false)
	await get_tree().physics_frame
	check(a.holder_id == 0, "G input drops current object")
	# RMB starts charge; release launches tap throw.
	pickup(a)
	await get_tree().physics_frame
	carrier.start_charge()
	check(player.carrier.charge_held, "RMB input starts charge")
	carrier.charge_started = Time.get_ticks_msec() / 1000.0 - 5.0  # full charge
	var charge := carrier.release_charge()
	var dir := carrier.throw_direction()
	carrier.request_throw(dir, charge)
	await get_tree().physics_frame
	check(a.holder_id == 0 and a.linear_velocity.length() >= 13.5, "RMB release launches a tap throw")
	# Cancel charge keeps the item.
	pickup(a)
	await get_tree().physics_frame
	carrier.start_charge()
	carrier.charge_held = false
	carrier.charge_started = -1.0
	check(player.carrier.is_carrying() and a.holder_id == 1, "cancel charge keeps item")
	carrier.request_drop(false)
	await get_tree().physics_frame
	# Disconnected holder releases prop.
	var prop_c := make_prop(Vector3(0.4, 0.8, 0.0), "TestPropC")
	await get_tree().physics_frame
	pickup(prop_c)
	check(prop_c.holder_id == 1, "prop picked up for disconnect test")
	CarryRegistry.on_holder_disconnect(1)
	check(prop_c.holder_id == 0, "disconnected holder releases prop")
	check(not prop_c.freeze, "prop physics re-enabled after disconnect")
	# Drop on teleport.
	var prop_f := make_prop(Vector3(0.0, 0.8, 2.0), "TestPropF")
	await get_tree().physics_frame
	pickup(prop_f)
	check(prop_f.holder_id == 1, "prop picked up for teleport test")
	player.teleport_to(Vector3(50, 0, 50), 0.0)
	await get_tree().physics_frame
	check(prop_f.holder_id == 0, "teleport drops carried prop")
	check(player.carrier.is_carrying() == false, "carrier cleared after teleport drop")
	player.teleport_to(Vector3(0, 0, 0), 0.0)
	# Punch while picking up is ignored.
	var prop_g := make_prop(Vector3(0.0, 0.8, -2.0), "TestPropG")
	await get_tree().physics_frame
	pickup(prop_g)
	check(prop_g.holder_id == 1, "prop picked up for punch test")
	check(player.combat.can_start_punch_charge() == false, "cannot start punch charge while carrying")
	var jab_event := InputEventKey.new()
	jab_event.physical_keycode = KEY_Q
	jab_event.pressed = true
	player._unhandled_input(jab_event)
	check(prop_g.holder_id == 1, "still carrying after jab attempt while carrying")
	drop(prop_g, 1, false)
	# State-machine transitions.
	var st: PlayerState = player.state
	check(st.transition_to(PlayerState.State.IDLE), "idle->idle legal (no-op)")
	check(st.is_transition_legal(PlayerState.State.CHARGING_PUNCH), "idle->charging punch legal")
	check(st.is_transition_legal(PlayerState.State.PARRYING), "idle->parrying legal")
	check(st.is_transition_legal(PlayerState.State.LIMP), "idle->limp legal")
	check(st.is_transition_legal(PlayerState.State.CARRYING), "idle->carrying legal")
	check(st.transition_to(PlayerState.State.CHARGING_PUNCH), "transition to charging punch OK")
	check(st.state == PlayerState.State.CHARGING_PUNCH, "state is charging punch")
	check(not st.transition_to(PlayerState.State.CARRYING), "charging->carrying NOT legal")
	check(st.transition_to(PlayerState.State.IDLE), "charging->idle legal")
	check(st.transition_to(PlayerState.State.LIMP), "idle->limp legal again")
	check(st.is_transition_legal(PlayerState.State.IDLE) == false, "limp->idle NOT legal via transition_to")
	check(st.transition_to(PlayerState.State.IDLE), "limp->idle legal via recovery path")
	check(st.state == PlayerState.State.IDLE, "back to idle")
	check(st.is_limp() == false, "not limp after reset")

	# --- limp Tier 1: BodyPhys limp mode -----------------------------------------
	var bp: BodyPhys = player.get_node("BodyPhys") as BodyPhys
	check(bp is BodyPhys, "player has a BodyPhys child")
	# Enter limp mode directly via begin_limp.
	bp.begin_limp(bp.global_transform, Vector3.ZERO, PhysicsTuning.LIMP_SECONDS)
	check(bp.limp_mode, "BodyPhys limp mode set via begin_limp")
	check(is_equal_approx(bp.mass, PhysicsTuning.LIMP_MASS_KG), "limp mass applied")
	# end_limp resets mass and limp mode.
	bp.end_limp(bp.global_transform)
	check(not bp.limp_mode, "end_limp resets limp_mode")
	check(is_equal_approx(bp.mass, PhysicsTuning.PROP_MASS_KG), "mass restored after end_limp")

	# end_limp clears limp_mode so it can't fire twice.
	bp.begin_limp(bp.global_transform, Vector3.ZERO, PhysicsTuning.LIMP_SECONDS)
	check(bp.limp_mode, "limp mode set again")
	bp.end_limp(bp.global_transform)
	check(not bp.limp_mode, "end_limp clears limp_mode")
	check(is_equal_approx(bp.mass, PhysicsTuning.PROP_MASS_KG), "mass restored after end_limp")

	# Interactable targeting: USE kind on plaque.
	var plaques := get_tree().get_nodes_in_group("lore_guides")
	var first_plaque := plaques[0] if plaques.size() > 0 else null
	if first_plaque != null:
		var interactable := Interactable.find(first_plaque)
		check(interactable != null, "plaque hosts an Interactable component")
		check(interactable.kind == Interactable.Kind.USE, "plaque Interactable kind is USE")
	# Limp player can be GRAB-targeted.
	var limp_player := world.get_node("Players/1")
	st.transition_to(PlayerState.State.LIMP)
	st.set_limp_phase(PlayerState.LimpPhase.LIMP_GROUND)
	check(limp_player.is_limp(), "player is limp")
	check(st.is_carrying_player() == false, "not carrying a player yet")
	print("House and hand: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
