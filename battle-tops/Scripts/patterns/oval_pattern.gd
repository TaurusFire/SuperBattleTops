class_name OvalPattern
extends MovementPattern

## Width relative to `scale`. 1.0 matches a circle.
@export var width_ratio := 1.0
## Height relative to `scale`. Lower than width_ratio gives a flattened oval.
@export var height_ratio := 0.4

func get_target(angle: float, scale: float, rot_phase: float) -> Vector2:
	var local := Vector2(cos(angle) * width_ratio, sin(angle) * height_ratio)
	return local.rotated(rot_phase) * scale
