class_name GameManager
extends Node

@export var arena: Arena
@export var tops: Array[Top]
@export var intro: IntroSequence

# collisions
@export var collision_radius := 0.08
@export var separation_radius := 0.11
@export var velocity_weight := 0.8

# game over
@export var slowmo_scale := 0.5

@export_group('Hitstop')
@export var hitstop_max_duration := 0.08
@export var hitstop_reference_damage := 120
@export var hitstop_reference_knockback := 30
@export var hitstop_threshold := 0.4
@export var hitstop_overrun := 2.0
@export_range(0.2, 3.0) var hitstop_curve := 1.4
var _hitstop_remaining := 0.0
var _hitstop_end_msec := 0


@export_group('Spawn Arrangement')
## Ring radius as a fraction of arena radius.
@export_range(0.0, 1.0) var spawn_radius_ratio := 0.6
## Rotates the whole ring. Randomise for variety between clips.
@export var spawn_angle_offset := 0.0
@export var randomise_spawn_rotation := true

@export_group('Ending')
## Deaths within this window of each other count as a draw.
@export var tie_window := 0.1
@export var freeze_delay := 1.5
var _first_stop_msec := 0
var _pending_end := false
var _window_deaths: Array[Top] = []

@export_group('Collision')
## Vertical separation beyond which two tops no longer count as touching.
## Roughly a top's height — above this, one is genuinely hopping over.
@export var vertical_threshold := 0.028

var _in_contact := {}

var countdown_seconds := 3.0
var time_remaining := 0.0

enum Phase { INTRO, COUNTDOWN, FIGHTING, ENDING, ENDED } 
var phase := Phase.COUNTDOWN
signal countdown_tick(seconds_left: int)
signal match_started
signal match_ended(winners: Array[Top])
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
		top.entered_dying.connect(_on_top_entered_dying)

	# Must precede the intro: the sequencer reads each top's position as the
	# destination it flies to.
	_arrange_tops()

	if intro != null:
		phase = Phase.INTRO
		intro.finished.connect(_on_intro_finished)
		intro.begin()
	else:
		_start_countdown()

func _on_intro_finished() -> void:
	_start_countdown()

func _start_countdown() -> void:
	for top in tops:
		top.begin_countdown()
	time_remaining = countdown_seconds
	phase = Phase.COUNTDOWN
	countdown_tick.emit(int(ceil(time_remaining)))

func _process(delta: float) -> void:
	# Hitstop freezes everything, so this must run on wall-clock time.
	if _hitstop_end_msec > 0:
		if Time.get_ticks_msec() >= _hitstop_end_msec:
			_hitstop_end_msec = 0
			# Restore to slow-mo if the match has already been decided.
			Engine.time_scale = slowmo_scale if phase == Phase.ENDING else 1.0
		return
		
	if _pending_end:
		if Time.get_ticks_msec() - _first_stop_msec >= int(tie_window * 1000.0):
			_resolve_end()
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
			var horizontal := _horizontal_distance(a, b)
			var vertical: float = absf(a.global_position.y - b.global_position.y)
			var threshold: float = a.radius + b.radius
			var touching := horizontal <= threshold and vertical <= vertical_threshold

			if not _in_contact.get(key, false) and touching:
				#print("collision: ", a.name, "<->", b.name)
				_resolve_collision(a, b)
				_in_contact[key] = true
			elif _in_contact.get(key, false) and horizontal > (threshold * 1.3) and vertical > (vertical_threshold * 1.3):
				_in_contact[key] = false
			elif horizontal > threshold or vertical > vertical_threshold:
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

	var a_bonus = a._velocity.dot(dir_ab) * velocity_weight
	var b_bonus = b._velocity.dot(dir_ba) * velocity_weight
	
	a.attack(b, a_bonus)
	b.attack(a, b_bonus)
	
	var threshold := a.radius + b.radius
	var gap := b_pos - a_pos
	var dist := gap.length()
	if dist < threshold and dist > 0.0001:
		var push := gap.normalized() * (threshold - dist) * 0.5
		a.global_position.x -= push.x
		a.global_position.z -= push.y
		b.global_position.x += push.x
		b.global_position.z += push.y
	
	collision_occurred.emit(a,b)
	
	
	_trigger_hitstop(
		max(a.last_damage_dealt, b.last_damage_dealt),
		max(a.last_knockback_dealt, b.last_knockback_dealt)
	)



func _on_top_entered_dying(top: Top) -> void:
	if phase == Phase.ENDED:
		return

	# Count tops not yet dying — this is the real measure of who's still in it.
	var alive := tops.filter(func(t): return t.current_state == Top.State.ACTIVE)

	if _pending_end:
		if not _window_deaths.has(top):
			_window_deaths.append(top)
		return

	if alive.size() <= 1:
		_pending_end = true
		_first_stop_msec = Time.get_ticks_msec()
		phase = Phase.ENDING
		_window_deaths = [top]
		_begin_slowmo()

func _living_tops() -> Array[Top]:
	return tops.filter(func(t): return t.current_state != Top.State.STOPPED \
									and t.current_state != Top.State.KNOCKED_OUT)

func _begin_slowmo() -> void:
	if phase != Phase.FIGHTING:
		return
	Engine.time_scale = slowmo_scale


func _trigger_hitstop(damage:float, knockback: float) -> void:
	if phase == Phase.COUNTDOWN or phase == Phase.ENDED:
		return
	var strength := (
		(knockback / hitstop_reference_knockback) + (damage / hitstop_reference_damage)
		)/2
	if strength < hitstop_threshold:
		return
	
	var shaped := pow(clamp(strength, 0.0, hitstop_overrun), hitstop_curve)
	var duration := hitstop_max_duration * shaped
	
	print("  -> freezing for %.3fs" % duration)
	_hitstop_end_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	Engine.time_scale = 0.05


func _resolve_end() -> void:
	_pending_end = false
	var still_fighting := tops.filter(
		func(t): return t.current_state == Top.State.ACTIVE)

	var winners: Array[Top] = []
	if still_fighting.size() >= 1:
		winners = still_fighting
	else:
		winners = _window_deaths

	_end_match(winners)


func _end_match(winners: Array[Top]) -> void:
	phase = Phase.ENDED
	Engine.time_scale = 1.0

	if winners.is_empty():
		print("Match over — no winner")
	elif winners.size() == 1:
		print("Winner: ", winners[0].display_name())
	else:
		var names := winners.map(func(t): return t.name)
		print("Draw between: ", ", ".join(names))

	match_ended.emit(winners)
	_freeze_after(freeze_delay)

func _freeze_after(delay: float) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	print("freezing; states: ", tops.map(func(t): return t.current_state))
	for t in tops:
		if t.current_state == Top.State.ACTIVE:
			t.freeze_in_place()
