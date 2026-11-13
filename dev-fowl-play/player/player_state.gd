class_name PlayerState extends RefCounted

## Single explicit player state machine (R4).
##
## The single answer to "what can this player do right now?". Input, interact,
## punch, pickup, movement lock, hover/glow and hands poses all query it.
##
## States:
##   IDLE             — free to move, punch, parry, pick up
##   CHARGING_PUNCH   — Q held for charged punch
##   PARRYING         — F held, parry grace window open
##   LIMP             — knockdown / ragdoll / carried / thrown (ONE concept)
##       LIMP_GROUND   lying on the ground, can be picked up
##       LIMP_CARRIED  being hauled by another player
##       LIMP_THROWN   airborne after being thrown
##   CARRYING         — holding an item or downed player
##
## transition_to() guards illegal transitions. can_*() queries are derived
## from state only — input handlers still own timing details (cooldowns,
## spam guards, charge meters).
##
## Per-state movement_locked / input_locked data replaces the old input_locked
## hacks and ragdolled_until scattered across player.gd / combat.gd.

enum State {
	IDLE,
	CHARGING_PUNCH,
	PARRYING,
	LIMP,
	CARRYING,
}

# LIMP sub-phase: how the limp body is currently being simulated.
enum LimpPhase {
	LIMP_GROUND,   # lying on the ground
	LIMP_CARRIED,  # being carried by another player
	LIMP_THROWN,   # airborne after being thrown
}

var state: State = State.IDLE
var limp_phase: LimpPhase = LimpPhase.LIMP_GROUND

# Seconds remaining before a limp player recovers (host-owned; 0 = not limp).
var limp_timer: float = 0.0

# Last time we entered the current state (seconds). Used by input handlers
# for cooldown/spam/timing math.
var state_entered_at: float = 0.0

signal state_changed(old: State, new: State)

# True iff `new_state` is a legal transition from the current state.
#
# Legal-transition matrix:
#   IDLE        -> CHARGING_PUNCH, PARRYING, CARRYING, LIMP
#   CHARGING_PUNCH -> IDLE, LIMP
#   PARRYING    -> IDLE, LIMP
#   LIMP        -> (no direct transitions; IDLE only via recovery path in transition_to)
#   CARRYING    -> IDLE, LIMP (drop what you carry first)
func is_transition_legal(new_state: State) -> bool:
	match state:
		State.IDLE:
			return new_state in [State.CHARGING_PUNCH, State.PARRYING, State.CARRYING, State.LIMP]
		State.CHARGING_PUNCH:
			return new_state in [State.IDLE, State.LIMP]
		State.PARRYING:
			return new_state in [State.IDLE, State.LIMP]
		State.LIMP:
			return false
		State.CARRYING:
			return new_state in [State.IDLE, State.LIMP]
	return false

# Attempt a state transition. Returns false if the transition is illegal.
#
# LIMP -> IDLE is permitted here as the recovery path (BodyPhys limp_recovered /
# limp timer expiry), even though is_transition_legal reports no direct LIMP
# transitions — recovery is the single sanctioned exit from LIMP.
func transition_to(new_state: State) -> bool:
	if new_state == state:
		return true
	if state == State.LIMP and new_state == State.IDLE:
		# Limp recovery: always legal, returns authority to owner.
		pass
	elif not is_transition_legal(new_state):
		push_warning("PlayerState: illegal transition %s -> %s" % [state, new_state])
		return false
	var old := state
	state = new_state
	state_entered_at = Time.get_ticks_msec() / 1000.0
	if new_state == State.LIMP:
		limp_phase = LimpPhase.LIMP_GROUND
		limp_timer = 0.0
	state_changed.emit(old, new_state)
	return true

# Set the LIMP sub-phase (ground / carried / thrown). Only meaningful while in LIMP.
func set_limp_phase(phase: LimpPhase) -> void:
	if state != State.LIMP:
		return
	limp_phase = phase

# Start a limp timer (seconds). Host-owned: when it expires the body emits
# limp_recovered via BodyPhys and transitions LIMP -> IDLE.
func start_limp_timer(seconds: float) -> void:
	limp_timer = seconds

# Tick the limp timer each physics frame. Returns true when it expired this frame.
func tick_limp_timer(delta: float) -> bool:
	if limp_timer <= 0.0:
		return false
	limp_timer -= delta
	if limp_timer <= 0.0:
		limp_timer = 0.0
		return true
	return false

# --- can_* queries -----------------------------------------------------------

func can_punch() -> bool:
	return state == State.IDLE

func can_parry() -> bool:
	return state == State.IDLE

func can_pickup() -> bool:
	return state == State.IDLE

func can_interact() -> bool:
	return state == State.IDLE

func is_idle() -> bool:
	return state == State.IDLE

# True while the player is limp (knocked down / ragdolled / carried / thrown).
func is_limp() -> bool:
	return state == State.LIMP

# True while the player is carrying something (item or downed player).
func is_carrying() -> bool:
	return state == State.CARRYING

func is_thrown() -> bool:
	return state == State.LIMP and limp_phase == LimpPhase.LIMP_THROWN

func is_carrying_player() -> bool:
	return state == State.LIMP and limp_phase == LimpPhase.LIMP_CARRIED

# True when this state locks player input (movement / jump / interact).
# LIMP (knocked down / carried / thrown) locks input; IDLE, CHARGING_PUNCH,
# PARRYING and CARRYING do not. Transient locks (lore typing, jab recovery)
# are handled separately by the player node.
func is_input_locked() -> bool:
	return state == State.LIMP

# How long the player has been in the current state (seconds).
func time_in_state() -> float:
	return Time.get_ticks_msec() / 1000.0 - state_entered_at
