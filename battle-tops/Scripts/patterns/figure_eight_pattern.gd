class_name FigureEightPattern
extends MovementPattern

@export var angular_speed := 2.0

func get_target(angle: float, scale: float, rot_phase: float) -> Vector2:
	var local = Vector2(sin(angle), sin(angle)*cos(angle)) * scale
	return local.rotated(rot_phase)
