class_name PhysicsLayers extends RefCounted

## Collision layer / mask table (brief 4.1). ONE source of truth.
##
## Layer  = what a body IS    (bit N-1, so layer 1 = bit value 1)
## Mask   = what a body HITS  (OR of layer bit values)
##
## Nothing sets layers or masks anywhere else in the codebase.

# Layer bit values (layer N = 1 << (N-1))
const LAYER_WORLD_STATIC: int = 1        # layer 1 — walls, floors, ceilings, fixed trim
const LAYER_DEVICES: int = 2             # layer 2 — buttons, keys, terminals, plaques, elevator button
const LAYER_PROPS: int = 4               # layer 3 — loose props
const LAYER_CARRIED: int = 8             # layer 4 — props/bodies being carried (collide with nothing)
const LAYER_HEALTHY_PLAYERS: int = 16    # layer 5 — player capsules
const LAYER_LIMP_BODIES: int = 32        # layer 6 — incapacitated player bodies (GRAB-able)
const LAYER_ELEVATOR: int = 64           # layer 7 — elevator door panels

# Ray masks
const MASK_FOCUS_RAY: int = \
	LAYER_DEVICES | LAYER_PROPS | LAYER_LIMP_BODIES   # only things you can act on right now
const MASK_LOS_RAY: int = \
	LAYER_WORLD_STATIC | LAYER_DEVICES | LAYER_PROPS | LAYER_HEALTHY_PLAYERS | \
	LAYER_LIMP_BODIES | LAYER_ELEVATOR                  # everything that blocks reach/sight

# Body masks
const MASK_WORLD_STATIC: int = \
	LAYER_WORLD_STATIC | LAYER_PROPS | LAYER_HEALTHY_PLAYERS | LAYER_LIMP_BODIES | LAYER_CARRIED
const MASK_DEVICES: int = LAYER_WORLD_STATIC | LAYER_HEALTHY_PLAYERS | LAYER_LIMP_BODIES
const MASK_PROPS: int = \
	LAYER_WORLD_STATIC | LAYER_PROPS | LAYER_HEALTHY_PLAYERS | LAYER_LIMP_BODIES
const MASK_CARRIED: int = 0                               # carried things collide with nothing
const MASK_HEALTHY_PLAYERS: int = \
	LAYER_WORLD_STATIC | LAYER_DEVICES | LAYER_PROPS | LAYER_LIMP_BODIES | LAYER_ELEVATOR
const MASK_LIMP_BODIES: int = \
	LAYER_WORLD_STATIC | LAYER_PROPS | LAYER_HEALTHY_PLAYERS | LAYER_LIMP_BODIES
const MASK_ELEVATOR: int = LAYER_WORLD_STATIC | LAYER_HEALTHY_PLAYERS | LAYER_LIMP_BODIES
