class_name BattleCamera
extends Node3D

@export var manager: GameManager
@export var arena: Arena
@onready var _cam: Camera3D = $Camera3D

var _focus := Vector3.ZERO
var _distance := 0.5

@export_group('Base Framing')
@export_range(0.0, 90.0) var pitch_degrees := 40.0
@export var distance := 0.45
@export var look_height := 0.02

@export_group('Tracking')
## How quickly the focus point catches up to the action. Lower = lazier.
@export var focus_lerp := 2.5
## How quickly distance responds to spread. Keep below focus_lerp so zoom lags.
@export var distance_lerp := 1.5
## Distance when the tops are on top of each other.
@export var distance_min := 0.3
## Distance when they're at opposite edges.
@export var distance_max := 0.5
## Spread (in world units) that maps to distance_max.
@export var spread_reference := 0.3
@export_range(0.0, 1.5) var focus_leash := 0.5

@export_group('Impact')
## Peak positional shake at reference knockback, in world units.
@export var shake_max := 0.003
## How fast shake decays. Higher = snappier.
@export var shake_decay := 8.0
## Shake oscillation speed.
@export var shake_frequency := 35.0
## How far the camera lunges toward the focus at reference knockback.
@export var punch_max := 0.05
## How fast the punch springs back.
@export var punch_decay := 5.0
## Knockback magnitude that earns the full effect.
@export var impact_reference := 1.0

var _shake := 0.0
var _punch := 0.0
var _shake_time := 0.0


func _ready() -> void:
	_cam.transform = Transform3D.IDENTITY
	_focus = Vector3(arena.centre.x, look_height, arena.centre.y)
	_distance = distance
	manager.collision_occurred.connect(_on_collision)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var living := _living_tops()

	var target_focus := Vector3(arena.centre.x, look_height, arena.centre.y)
	var target_distance := distance_max

	if not living.is_empty():
		var sum := Vector2.ZERO
		for t in living:
			sum += t._horizontal_pos()
		var mid: Vector2 = sum / living.size()
		target_focus = Vector3(mid.x, look_height, mid.y)
		target_distance = lerp(distance_min, distance_max,
			clamp(_spread(living) / spread_reference, 0.0, 1.0))
		
		# Leash the focus to the arena, so a top flying out or a lopsided
		# midpoint can't drag the frame off the fight.
		var centre = Vector3(arena.centre.x, look_height, arena.centre.y)
		var from_centre = target_focus - centre
		from_centre.y = 0.0
		var leash = arena.radius * focus_leash
		if from_centre.length() > leash:
			target_focus = centre + from_centre.normalized() * leash

	_focus = _focus.lerp(target_focus, clamp(focus_lerp * delta, 0.0, 1.0))
	_distance = lerp(_distance, target_distance, clamp(distance_lerp * delta, 0.0, 1.0))
	_place(_focus, _distance)
	_update_impact(delta)
	
func _living_tops() -> Array:
	return manager.tops.filter(func(t):
		return t.current_state in [Top.State.ACTIVE, Top.State.DYING])

## Largest pairwise separation — generalises past two tops.
func _spread(tops: Array) -> float:
	var widest := 0.0
	for i in tops.size():
		for j in range(i + 1, tops.size()):
			widest = max(widest, tops[i]._horizontal_pos().distance_to(tops[j]._horizontal_pos()))
	return widest

func _place(focus: Vector3, dist: float) -> void:
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * dist
	global_position = focus + offset
	look_at(focus, Vector3.UP)


func _on_collision(a: Top, b: Top) -> void:
	var strength = clamp(max(a.last_knockback_dealt, b.last_knockback_dealt) / impact_reference, 0.0, 1.0)
	_shake = max(_shake, strength)
	_punch = max(_punch, strength)


func _update_impact(delta: float) -> void:
	_shake = max(_shake - shake_decay * delta * _shake, 0.0)
	_punch = max(_punch - punch_decay * delta * _punch, 0.0)
	_shake_time += delta * shake_frequency

	# Shake: high-frequency wobble in the camera's own screen plane.
	var offset := Vector3.ZERO
	if _shake > 0.001:
		offset.x = sin(_shake_time * 1.0) * shake_max * _shake
		offset.y = sin(_shake_time * 1.37) * shake_max * _shake

	# Punch: lunge forward along the camera's view direction.
	offset.z = -punch_max * _punch

	_cam.position = offset
