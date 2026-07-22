class_name GameManager
extends Node

@export var arena: Arena
@export var tops: Array[Top]

# collisions
@export var collision_radius := 0.08
@export var separation_radius := 0.11
@export var velocity_weight := 0.45

# game over
@export var slowmo_scale := 0.5

@export_group('Hitstop')
@export var hitstop_max_duration := 0.05
@export var hitstop_reference_damage := 60
@export var hitstop_reference_knockback := 1
@export var hitstop_threshold := 0.2
var _hitstop_remaining := 0.0
var _hitstop_end_msec := 0


@export_group('Spawn Arrangement')
## Ring radius as a fraction of arena radius.
@export_range(0.0, 1.0) var spawn_radius_ratio := 0.6
## Rotates the whole ring. Randomise for variety between clips.
@export var spawn_angle_offset := 0.0
@export var randomise_spawn_rotation := true


var _in_contact := {}

var countdown_seconds := 3.0
var time_remaining := 0.0

enum Phase {COUNTDOWN, FIGHTING, ENDING, ENDED} 
var phase := Phase.COUNTDOWN
signal countdown_tick(seconds_left: int)
signal match_started
signal match_ended(winner: Top)
signal collision_occurred(a: Top, b: Top)


func _ready() -> void:
	assert(not tops.is_empty(), "GameManager: tops array is unassigned!")
	assert(arena != null, "GameManager: arena is unassigned!")
	
	for top in tops:
		top._set_arena(
			arena.centre,
			arena.radius,
			arena.wall_radius,
			arena.wall_bounce,
			arena.wall_damage,
			arena.gravity,
			arena.knockout_radius
		)
		top.opponents = tops.filter(func(t): return t != top)
		top.stopped.connect(_on_top_stopped)
		top.entered_dying.connect(_on_top_entered_dying)
		
	_arrange_tops()
	
	time_remaining = countdown_seconds
	phase = Phase.COUNTDOWN

func _process(delta: float) -> void:
	# Hitstop freezes everything, so this must run on wall-clock time.
	if _hitstop_end_msec > 0:
		if Time.get_ticks_msec() >= _hitstop_end_msec:
			_hitstop_end_msec = 0
			# Restore to slow-mo if the match has already been decided.
			Engine.time_scale = slowmo_scale if phase == Phase.ENDING else 1.0
		return
	if phase != Phase.COUNTDOWN:
		return
	var before = ceil(time_remaining)
	time_remaining = max(time_remaining - delta, 0.0)
	for top in tops:
		top.set_countdown_remaining(time_remaining)
	var after = ceil(time_remaining)
	if after != before and after > 0:
		countdown_tick.emit(int(after))
	if time_remaining <= 0.0:
		_start_match()

func _physics_process(delta: float) -> void:
	if phase != Phase.FIGHTING:
		return
	_check_collisions()
	

func _horizontal_distance(a: Top, b: Top) -> float:
	return Vector2(a.global_position.x, a.global_position.z).distance_to(
		Vector2(b.global_position.x, b.global_position.z)
	)

func _both_fightable(a: Top, b: Top) -> bool:
	return a.current_state == Top.State.ACTIVE and b.current_state == Top.State.ACTIVE

func _check_collisions() -> void:
	for i in tops.size():
		for j in range(i+1, tops.size()):
			var a := tops[i]
			var b := tops[j]
			if not _both_fightable(a, b):
				continue
			var key = str(i) + "_" + str(j)
			var dist = _horizontal_distance(a, b)
			var threshold = a.radius + b.radius
			if not _in_contact.get(key, false) and dist < threshold:
				#print("collision: ", a.name, "<->", b.name)
				_resolve_collision(a, b)
				_in_contact[key] = true
			elif _in_contact.get(key, false) and dist >= (threshold * 1.3):
				_in_contact[key] = false
	
func _start_match() -> void:
	phase = Phase.FIGHTING
	for top in tops:
		top.begin_match()
	match_started.emit()
	

func _arrange_tops() -> void:
	var ring := arena.radius * spawn_radius_ratio
	var base := spawn_angle_offset
	if randomise_spawn_rotation:
		base = randf() * TAU

	for i in tops.size():
		var angle := base + TAU * float(i) / tops.size()
		var pos := arena.centre + Vector2(cos(angle), sin(angle)) * ring
		var top := tops[i]
		top.global_position = Vector3(pos.x, top.global_position.y, pos.y)
		

func _resolve_collision(a: Top, b: Top) -> void:
	var a_pos := Vector2(a.global_position.x, a.global_position.z)
	var b_pos := Vector2(b.global_position.x, b.global_position.z)

	var dir_ab := (b_pos - a_pos)
	dir_ab = dir_ab.normalized() if dir_ab.length() > 0.001 else Vector2.RIGHT
	var dir_ba := -dir_ab

	var a_bonus = max(a._velocity.dot(dir_ab), 0.0) * velocity_weight
	var b_bonus = max(b._velocity.dot(dir_ba), 0.0) * velocity_weight

	a.attack(b, a_bonus)
	b.attack(a, b_bonus)

	_trigger_hitstop(
		max(a.last_damage_dealt, b.last_damage_dealt),
		max(a.last_knockback_dealt, b.last_knockback_dealt)
	)
	collision_occurred.emit(a,b)

func _on_top_stopped(stopped_top: Top) -> void:

	if phase == Phase.ENDED:
		return
	var survivors = _living_tops()
	if survivors.size() <= 1:
		_end_match(survivors)

func _on_top_entered_dying(_top: Top) -> void:
	var still_fighting := tops.filter(func(t): return t.current_state == Top.State.ACTIVE)
	if still_fighting.size() <= 1:
		_begin_slowmo()

func _living_tops() -> Array[Top]:
	return tops.filter(func(t): return t.current_state != Top.State.STOPPED \
									and t.current_state != Top.State.KNOCKED_OUT)

func _begin_slowmo() -> void:
	
	if phase != Phase.FIGHTING:
		return
	
	phase = Phase.ENDING
	Engine.time_scale = slowmo_scale

func _end_match(survivors: Array[Top]) -> void:
	Engine.time_scale = 1.0
	phase = Phase.ENDED
	var winner: Top = survivors[0] if survivors.size() == 1 else null
	match_ended.emit(winner)
	# end sequence goes here

func _trigger_hitstop(damage:float, knockback: float) -> void:
	if phase != Phase.FIGHTING:
		return
	var strength := (
		(knockback / hitstop_reference_knockback) + (damage / hitstop_reference_damage)
		)/2
	if strength < hitstop_threshold:
		return
	var duration = hitstop_max_duration * clamp(strength, 0.0, 1.0)
	print("hitstop strength: ", clamp(strength, 0.0, 1.0), ", hitstop duration: ", duration)
	_hitstop_end_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	Engine.time_scale = 0.0
