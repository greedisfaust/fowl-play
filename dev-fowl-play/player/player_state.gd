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

var state: State = IDLE

# Last time we entered the current state (seconds). Used by input handlers
# for cooldown/spam/timing math.
var state_entered_at: float := 0.0

signal state_changed(old: State, new: State)

# True iff `new_state` is a legal transition from the current state.
func is_transition_legal(new_state: State) -> bool:
	match state:
		IDLE:
			return new_state in [CHARGING_PUNCH, PARRYING, CARRYING, KNOCKED_DOWN, CARRIED]
		CHARGING_PUNCH:
			return new_state in [IDLE, KNOCKED_DOWN]
		PARRYING:
			return new_state in [IDLE, KNOCKED_DOWN]
		KNOCKED_DOWN:
			return new_state in [IDLE, CARRIED]
		CARRYING:
			return new_state in [IDLE, KNOCKED_DOWN]
		CARRIED:
			return new_state in [IDLE, RAGDOLL]
		THROWN:
			return new_state in [IDLE]
		RAGDOLL:
			return new_state in [IDLE]

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
	return state in [IDLE]

func can_parry() -> bool:
	return state in [IDLE]

func can_pickup() -> bool:
	return state in [IDLE]

func can_interact() -> bool:
	return state in [IDLE]

func is_idle() -> bool:
	return state == IDLE

func is_knocked_down() -> bool:
	return state == KNOCKED_DOWN

func is_carried() -> bool:
	return state == CARRIED

func is_ragdoll() -> bool:
	return state == RAGDOLL

func is_carrying() -> bool:
	return state == CARRYING

func is_thrown() -> bool:
	return state == THROWN
