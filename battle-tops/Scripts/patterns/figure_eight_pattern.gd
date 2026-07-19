class_name FigureEightPattern
extends MovementPattern

func get_target(angle: float, scale: float, rot_phase: float) -> Vector2:
	var local = Vector2(sin(angle)*1.1, sin(angle)*cos(angle) * 1.3) 
	return local.rotated(rot_phase) * scale
