class_name BattleCamera
extends Node3D

@export var manager: GameManager
@export var arena: Arena

@export_group('Base Framing')
@export_range(0.0, 90.0) var pitch_degrees := 40.0
@export var distance := 0.45
@export var look_height := 0.02

@onready var _cam: Camera3D = $Camera3D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_cam.transform = Transform3D.IDENTITY


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var focus := Vector3(arena.centre.x, look_height, arena.centre.y)
	_place(focus)
	
func _place(focus: Vector3) -> void:
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * distance
	global_position = focus + offset
	look_at(focus, Vector3.UP)
