class_name PhysicsTuning extends Node

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

const LIMP_SECONDS: float = 3.5                # how long a limp player stays down

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

# --- limp body safety and feel (meters / seconds / m/s) --------------------

const CHARGED_PUNCH_LIFT_RATIO: float = 0.5   # vertical share of the knockdown launch (~27 deg up)
const BODY_MAX_SPEED_MPS: float = 20.0        # hard speed clamp for any simulated body
const BODY_KILL_PLANE_Y_M: float = -10.0      # below this, a body is returned to its last safe spot
const LIMP_SETTLED_SPEED_MPS: float = 1.0     # below this speed a limp body counts as at rest
const LIMP_MAX_SECONDS: float = 6.0           # hard cap of free tumbling: recovery ALWAYS happens
const LIMP_TUMBLE_SPIN_RADPS: float = 3.0     # tumble spin added to a knockdown
const SNAPSHOT_FOLLOW_RATE: float = 12.0      # client smoothing toward host snapshots (1/s)
const LIMP_CAMERA_HEIGHT_M: float = 0.5       # owner's camera height while lying down

## Knockdown launch velocity: mostly horizontal with a fixed upward share, never above BODY_MAX_SPEED_MPS.
static func knockdown_velocity(flat_dir: Vector3, speed: float) -> Vector3:
	var d: Vector3 = Vector3(flat_dir.x, 0.0, flat_dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	return Vector3(d.x, CHARGED_PUNCH_LIFT_RATIO, d.z).normalized() * minf(speed, BODY_MAX_SPEED_MPS)

# --- hitbox (meters / seconds / m/s) ---------------------------------------

const QUICK_PUNCH_RANGE_M: float = 2.5          # quick punch reach
const QUICK_PUNCH_SIZE_M: float = 0.9           # quick punch hitbox radius
const QUICK_PUNCH_DURATION_S: float = 0.10      # quick punch hitbox lifetime
const QUICK_PUNCH_JIGGLE_SPEED_MPS: float = 2.0 # jiggle impulse on quick hit

const CHARGED_PUNCH_RANGE_M: float = 3.5        # charged punch reach
const CHARGED_PUNCH_SIZE_M: float = 1.4         # charged punch hitbox radius
const CHARGED_PUNCH_DURATION_S: float = 0.20    # charged punch hitbox lifetime
const CHARGED_PUNCH_PUSH_SPEED_MPS: float = 6.0 # charged punch push speed
const CHARGED_PUNCH_RAGDOLL_SECONDS: float = 3.5 # how long target stays limp

const PARRY_WINDIN_SECONDS: float = 0.3         # F press -> stance active
const PARRY_ACTIVE_SECONDS: float = 0.6         # active parry window
const PARRY_RECOVERY_SECONDS: float = 0.6       # stance drops, can't parry yet
const PARRY_BARRIER_RADIUS_M: float = 1.2       # barrier cylinder radius
const PARRY_BARRIER_HEIGHT_M: float = 2.0       # barrier cylinder height

# --- derived ---

## Total parry cycle: wind-in + active + recovery (seconds).
static func get_parry_cycle_seconds() -> float:
	return PARRY_WINDIN_SECONDS + PARRY_ACTIVE_SECONDS + PARRY_RECOVERY_SECONDS
