extends Node

@export var manager: GameManager
@export var marker_scene: PackedScene

var _markers := {}

func _ready() -> void:
	for top in manager.tops:
		var m: TargetMarker = marker_scene.instantiate()
		add_child(m)
		_markers[top] = m
		top.target_locked.connect(_on_locked)
		top.target_released.connect(_on_released)

func _on_locked(top: Top, target: Top, tint: Color) -> void:
	_markers[top].lock_on(target, tint)

func _on_released(top: Top) -> void:
	_markers[top].release()
