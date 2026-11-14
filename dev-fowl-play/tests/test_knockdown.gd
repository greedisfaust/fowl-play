extends Node

## Headless knockdown check (R4): host knocks a player down via host_knock_down,
## the player enters LIMP with BodyPhys limp_mode active, and recovers to IDLE
## after the limp timer expires (host single recovery clock).
## Runs as local host (peer 1) with no ENet peer.

const BodyPhys := preload("res://autoload/body_phys.gd")
const PlayerState := preload("res://player/player_state.gd")
var failures := 0
var checks := 0
var world: Node3D

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _ready() -> void:
	print("KNOCKDOWN TEST: starting")
	world = preload("res://world.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame

	var player: Node = world.get_node("Players/1")
	var st: PlayerState = player.get("state") as PlayerState
	var bp: BodyPhys = player.get_node("BodyPhys") as BodyPhys
	print("KNOCKDOWN TEST: player found, state=", st, "bp=", bp, "is_server=", multiplayer.is_server())

	# 1. Player starts IDLE, not limp.
	check(st.state == PlayerState.State.IDLE, "player starts IDLE")
	check(st.is_limp() == false, "player not limp at start")
	check(not bp.limp_mode, "BodyPhys not limp at start")

	# 2. Host knocks the player down.
	print("KNOCKDOWN TEST: calling host_knock_down")
	player.call("host_knock_down", Vector3(0, 0, -1), 6.0, PhysicsTuning.LIMP_SECONDS)
	await get_tree().physics_frame
	print("KNOCKDOWN TEST: after knockdown, st.is_limp=", st.is_limp(), "bp.limp_mode=", bp.limp_mode)
	check(st.is_limp(), "player is limp after host_knock_down")
	check(st.limp_phase == PlayerState.LimpPhase.LIMP_GROUND, "limp phase is LIMP_GROUND")
	check(bp.limp_mode, "BodyPhys limp_mode active after knockdown")
	check(is_equal_approx(bp.mass, PhysicsTuning.LIMP_MASS_KG), "limp mass applied")
	check(st.is_input_locked(), "input locked while limp")

	# 3. Calling host_knock_down again while limp is a no-op (already down).
	var was_limp := bp.limp_mode
	player.call("host_knock_down", Vector3(0, 0, -1), 6.0, PhysicsTuning.LIMP_SECONDS)
	await get_tree().physics_frame
	check(bp.limp_mode == was_limp, "second knockdown while limp is a no-op")

	# 4. Wait for the limp timer to expire and recover to IDLE.
	# LIMP_SECONDS = 2.5, but recovery also needs the body settled (< 1 m/s)
	# or the LIMP_MAX_SECONDS = 6.0 hard cap. Poll up to 8 seconds.
	var waited := 0.0
	while st.is_limp() and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	check(not st.is_limp(), "player recovers to IDLE after limp timer expires")
	check(st.state == PlayerState.State.IDLE, "state is IDLE after recovery")
	check(not bp.limp_mode, "BodyPhys limp_mode cleared after recovery")
	check(is_equal_approx(bp.mass, PhysicsTuning.PROP_MASS_KG), "mass restored after recovery")
	check(st.is_input_locked() == false, "input unlocked after recovery")

	# 5. The player can be knocked down again after recovery (fresh clock).
	player.call("host_knock_down", Vector3(0, 0, -1), 6.0, PhysicsTuning.LIMP_SECONDS)
	await get_tree().physics_frame
	check(st.is_limp(), "player can be knocked down again after recovery")
	st.transition_to(PlayerState.State.IDLE)   # clean up for the test harness
	bp.end_limp(bp.global_transform)

	print("Knockdown: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
