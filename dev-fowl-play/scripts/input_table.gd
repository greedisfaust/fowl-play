class_name InputTable extends RefCounted

## Pure input / state resolution (brief 6.1, testability requirement DECIDED).
##
## `resolve(state, input, held_seconds) -> action` is a pure function with no
## node dependencies — headless-testable. The state machine's transition table
## is data (PlayerState), no node references here.
##
## Inputs: "left_click", "e", "q_press", "q_release", "f"
## States:   "idle", "charging_punch", "parrying", "limp", "carrying"
## Actions:  "press_device", "grab", "jab", "drop", "wind_up", "throw_charge",
##           "charged_punch", "parry", "blocked", "none"

enum Action {
	PRESS_DEVICE,
	GRAB,
	JAB,
	DROP,
	WIND_UP,
	THROW_CHARGE,
	CHARGED_PUNCH,
	PARRY,
	BLOCKED,
	NONE,
}

## Resolve one input in one state. `held_seconds` is how long Q has been held
## (only meaningful for "q_release"; pass 0.0 otherwise).
## Returns (Action, throw_charge: float) — charge is 0..1 for THROW_CHARGE.
func resolve(state: String, input: String, held_seconds: float = 0.0) -> Array:
	# --- idle, not holding ---------------------------------------------------
	if state == "idle":
		match input:
			"left_click":
				return [Action.PRESS_DEVICE, 0.0]
			"e":
				return [Action.GRAB, 0.0]   # caller decides USE vs GRAB by aim kind
			"q_press":
				return [Action.WIND_UP, 0.0]
			"q_release":
				if held_seconds < PhysicsTuning.TAP_MAX_SECONDS:
					return [Action.JAB, 0.0]   # tap = quick punch (jab)
				return [Action.WIND_UP, 0.0]   # fizzles, short recovery
			"f":
				return [Action.PARRY, 0.0]
			_:
				return [Action.NONE, 0.0]

	# --- holding item or limp player -----------------------------------------
	if state == "carrying":
		match input:
			"left_click":
				return [Action.BLOCKED, 0.0]
			"e":
				return [Action.BLOCKED, 0.0]
			"q_press":
				return [Action.THROW_CHARGE, 0.0]   # start charging a throw
			"q_release":
				# tap drops; longer hold commits to throw on release.
				var charge := clampf(held_seconds / PhysicsTuning.THROW_FULL_CHARGE_SECONDS, 0.0, 1.0)
				if held_seconds < PhysicsTuning.TAP_MAX_SECONDS:
					return [Action.DROP, 0.0]
				return [Action.THROW_CHARGE, charge]
			"f":
				return [Action.BLOCKED, 0.0]
			_:
				return [Action.NONE, 0.0]

	# --- charged-punch state (wind-up / lunge / recovery) --------------------
	if state == "charging_punch":
		# use, grab, parry blocked; becoming limp ends it immediately
		match input:
			"left_click":
				return [Action.BLOCKED, 0.0]
			"e":
				return [Action.BLOCKED, 0.0]
			"q_press":
				return [Action.NONE, 0.0]   # already winding up
			"q_release":
				return [Action.NONE, 0.0]   # host auto-fires at charged_punch_hold_seconds
			"f":
				return [Action.BLOCKED, 0.0]
			_:
				return [Action.NONE, 0.0]

	# --- limp ----------------------------------------------------------------
	if state == "limp":
		# all inputs blocked while limp
		return [Action.BLOCKED, 0.0]

	# --- parrying ------------------------------------------------------------
	if state == "parrying":
		match input:
			"f":
				return [Action.NONE, 0.0]   # parry grace; cooldown after release
			_:
				return [Action.NONE, 0.0]

	return [Action.NONE, 0.0]

