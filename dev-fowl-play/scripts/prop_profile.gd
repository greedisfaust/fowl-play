class_name PropProfile extends Resource

## Per-prop profile picked from the Inspector. One profile can be shared by many
## props (e.g. all "light" cups use the same profile). No per-prop magic numbers
## anywhere — weight class, pickup, throw, friction/bounce, size, sound all live here.

enum WeightClass { LIGHT, MEDIUM, HEAVY, IMMOVABLE }

@export var weight_class: WeightClass = WeightClass.LIGHT
@export var pickup_allowed: bool = true
@export var throwable: bool = true
@export var friction: float = 0.5
@export var bounce: float = 0.3
@export var size_class: String = "small"   # "small", "medium", "large"
@export var impact_sound_path: String = "" # optional; empty = default impact sound
