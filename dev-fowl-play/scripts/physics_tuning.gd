class_name PhysicsTuning

## Single tuning source for all physics/input numbers.
## Every constant lives here, with units in the name. One job per file.
## All times are seconds unless the name says otherwise; all speeds are m/s.
##
## TODO: migrate these consts into resources/physics_tuning.tres once the
## .tres bootstrap ordering works headless (class_name registration timing).

# --- input timing (seconds) -------------------------------------------------

const TAP_MAX_SECONDS: float = 0.25            # press released within this = tap
const CHARGED_PUNCH_HOLD_SECONDS: float = 1.0  # Q hold this long = charged punch auto-fires
const CHARGED_PUNCH_COOLDOWN_SECONDS: float = 2.0  # before another charged punch can start
const JAB_COOLDOWN_SECONDS: float = 0.35       # jab spam guard
const THROW_FULL_CHARGE_SECONDS: float = 1.25  # hold time for full throw charge

# --- throw speed (m/s) ------------------------------------------------------

const MIN_THROW_SPEED_MPS: float = 3.0         # tap throw
const MAX_THROW_SPEED_MPS: float = 14.0        # full charged throw

# --- parry (seconds) --------------------------------------------------------

const PARRY_GRACE_SECONDS: float = 1.5         # max seconds parry stays active while holding F
const PARRY_COOLDOWN_SECONDS: float = 1.5      # before F can parry again

# --- limp (seconds) ---------------------------------------------------------

const LIMP_SECONDS: float = 2.5                # how long a limp player stays down

# --- punch (m/s) ------------------------------------------------------------

const PUNCH_RANGE_M: float = 3.0               # charged punch reach
const LUNGE_SPEED_MPS: float = 12.0            # charged punch lunge

# --- physics ----------------------------------------------------------------

const GRAVITY_SCALE: float = 1.0
const LINEAR_DAMP: float = 0.15
const ANGULAR_DAMP: float = 0.5
const REACH_M: float = 3.2                     # pickup/reach distance
const SNAPSHOT_RATE_HZ: float = 15.0           # host snapshot interval (Hz)
const IMPACT_SPEED_THRESHOLD_MPS: float = 8.0  # wall-slam VFX fires above this
const LIMP_MASS_KG: float = 8.0                # limp players are heavy
const PROP_MASS_KG: float = 0.6                # small carryable props
const LARGE_PROP_MASS_KG: float = 4.0          # furniture / large props
const LIMP_SWING_LAG: float = 8.0              # spring follow speed for carried limp bodies

# --- derived ----------------------------------------------------------------

## Snapshot interval in seconds, computed from SNAPSHOT_RATE_HZ.
static func get_snapshot_interval_seconds() -> float:
	return 1.0 / max(SNAPSHOT_RATE_HZ, 0.1)
