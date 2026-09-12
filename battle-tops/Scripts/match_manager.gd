class_name MatchManager
extends Node

## Runs a best-of-N above the round manager. Set `rounds_to_win` to 1 for a
## single game — free-for-alls and one-off clips still work unchanged.

signal round_starting(round_number: int, scores: Dictionary)
signal match_complete(winners: Array[Top], scores: Dictionary)

@export var manager: GameManager
@export var rounds_to_win := 2
## Countdown for the opening round. Later rounds get the shorter one, since
## the viewer has already had the full ceremony.
@export var first_countdown := 3.0
@export var later_countdown := 1.0
## Pause between a round's result and the next beginning. Kept short — a gap
## is where a viewer scrolls away.
@export var finish_display: FinishDisplay
@export var round_display: RoundDisplay
@export var result_display: ResultDisplay

var scores := {}
var round_number := 0
var _match_over := false


func _ready() -> void:
	assert(manager != null, "MatchManager: manager is unassigned.")
	for top in manager.tops:
		scores[top] = 0
	manager.round_ended.connect(_on_round_ended)
	if result_display != null:
		result_display.result_dismissed.connect(_on_result_dismissed)
	# Ready runs children first, so the manager has finished its own setup.
	call_deferred("_begin_round")


## Marker the manager checks for, so it knows not to start itself.
func register_manager() -> void:
	pass


func _begin_round() -> void:
	round_number += 1

	if round_number == 1 and manager.intro != null:
		manager.play_intro(first_countdown)
		# Announced after the fly-in rather than before it: the banner belongs
		# to the fight starting, not to the fighters arriving.
		await manager.intro_complete
		round_starting.emit(round_number, scores)
		if round_display != null:
			await round_display.dismissed
		manager.start_round(first_countdown)
		return

	manager.prepare_round()
	round_starting.emit(round_number, scores)
	if round_display != null:
		await round_display.dismissed
	manager.start_round(later_countdown)


func _on_round_ended(winners: Array[Top]) -> void:
	if _match_over:
		return

	for w in winners:
		if scores.has(w):
			scores[w] += 1

	# Who has reached the target, not who won the round — a drawn round
	# advances both fighters but only one of them may be at match point.
	var at_target: Array[Top] = []
	for top in scores:
		if scores[top] >= rounds_to_win:
			at_target.append(top)

	if not at_target.is_empty():
		_match_over = true
		match_complete.emit(at_target, scores)
		return

	var remaining = (rounds_to_win * 2 - 1) - round_number
	if remaining <= 0:
		_match_over = true
		match_complete.emit(_leaders(), scores)
		return

	await get_tree().process_frame
	if manager.has_dying_tops():
		await manager.round_settled
		await get_tree().process_frame

	if finish_display != null and finish_display.visible:
		await finish_display.dismissed

	_begin_round()


func would_end_match(winners: Array[Top]) -> bool:
	for w in winners:
		if scores.has(w) and scores[w] + 1 >= rounds_to_win:
			return true
	return round_number >= rounds_to_win * 2 - 1

func _on_result_dismissed() -> void:
	manager.freeze_tops(0.0)
	

func _leaders() -> Array[Top]:
	var best = 0
	for top in scores:
		best = max(best, scores[top])
	var out: Array[Top] = []
	for top in scores:
		if scores[top] == best:
			out.append(top)
	return out
