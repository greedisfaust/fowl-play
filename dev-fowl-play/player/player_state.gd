class_name PlayerState extends RefCounted

## Single explicit player state machine.
##
## States:
##   IDLE            — free to move, punch, parry, pick up
##   CHARGING_PUNCH  — Q held for charged punch
##   PARRYING        — F held, parry grace window open
##   KNOCKED_DOWN    — stunned, can't act, getting back up soon
##   CARRYING        — holding an item or downed player
##   CARRIED         — being carried by another player (downed)
##   THROWN          — in flight after being thrown
##   RAGDOLL         — tumbling physics body (downed, tumbling, carryable)
##
## transition_to() guards illegal transitions. can_*() queries are derived
## from state only — input handlers still own timing details (cooldowns,
## spam guards, charge meters).

enum State {
	IDLE,
	CHARGING_PUNCH,
	PARRYING,
	KNOCKED_DOWN,
	CARRYING,
	CARRIED,
	THROWN,
	RAGDOLL,
}

var state: State = State.IDLE

# Last time we entered the current state (seconds). Used by input handlers
# for cooldown/spam/timing math.
var state_entered_at: float = 0.0

# How long (seconds) the player stays ragdolled after being hit. 0 = not ragdolled.
var ragdolled_until: float = 0.0

signal state_changed(old: State, new: State)

# True iff `new_state` is a legal transition from the current state.
func is_transition_legal(new_state: State) -> bool:
	match state:
		State.IDLE:
			return new_state in [State.CHARGING_PUNCH, State.PARRYING, State.CARRYING, State.KNOCKED_DOWN, State.CARRIED]
		State.CHARGING_PUNCH:
			return new_state in [State.IDLE, State.KNOCKED_DOWN]
		State.PARRYING:
			return new_state in [State.IDLE, State.KNOCKED_DOWN]
		State.KNOCKED_DOWN:
			return new_state in [State.IDLE, State.CARRIED]
		State.CARRYING:
			return new_state in [State.IDLE, State.KNOCKED_DOWN]
		State.CARRIED:
			return new_state in [State.IDLE, State.RAGDOLL]
		State.THROWN:
			return new_state in [State.IDLE]
		State.RAGDOLL:
			return new_state in [State.IDLE]
	return false

# Attempt a state transition. Returns false if the transition is illegal.
func transition_to(new_state: State) -> bool:
	if new_state == state:
		return true
	if not is_transition_legal(new_state):
		push_warning("PlayerState: illegal transition %s -> %s" % [state, new_state])
		return false
	var old := state
	state = new_state
	state_entered_at = Time.get_ticks_msec() / 1000.0
	state_changed.emit(old, new_state)
	return true

# --- can_* queries -------------------------------------------------------

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

func is_knocked_down() -> bool:
	return state == State.KNOCKED_DOWN

func is_carried() -> bool:
	return state == State.CARRIED

func is_ragdoll() -> bool:
	return state == State.RAGDOLL

func is_carrying() -> bool:
	return state == State.CARRYING

func is_thrown() -> bool:
	return state == State.THROWN

# True while the player is ragdolled (hit, tumbling, can be carried).
func is_ragdolled() -> bool:
	return ragdolled_until > Time.get_ticks_msec() / 1000.0
