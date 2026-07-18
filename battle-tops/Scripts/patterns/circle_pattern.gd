class_name CirclePattern
extends MovementPattern

func get_target(angle: float, scale: float, rot_phase: float) -> Vector2:
	var local = Vector2(cos(angle), sin(angle)) * scale
	return local.rotated(rot_phase)
