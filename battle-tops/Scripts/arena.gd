class_name Arena
extends StaticBody3D

@export var centre := Vector2(0,0)
@export var knockout_radius : float = 0.20
@export var radius := 0.16
@export var wall_radius := 0.17
@export var wall_bounce := 0.5
@export var wall_damage := 50
@export var gravity := 1.1

func _ready() -> void:
	pass # Replace with function body.

func _process(delta: float) -> void:
	pass
