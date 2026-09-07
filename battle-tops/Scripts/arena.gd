class_name Arena
extends StaticBody3D

@export var centre := Vector2(0,0)
@export var knockout_radius : float = 0.17
@export var radius := 0.155
@export var wall_radius := 0.165
@export var wall_bounce := 0.65
@export var wall_damage := 100
@export var gravity := 1.0
@export var bowl_curve := 0.8   # the K in y = K·r²
@export var wall_top_height := 0.076
@export var display_name := "BASIC ARENA"

func _ready() -> void:
	pass # Replace with function body.

func _process(delta: float) -> void:
	pass
