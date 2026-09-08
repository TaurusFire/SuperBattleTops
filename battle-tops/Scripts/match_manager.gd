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
@export var between_rounds := 2.2
@export var round_announce_pause := 0.0
@export var match_freeze_delay := 6.0

var scores := {}
var round_number := 0
var _match_over := false


func _ready() -> void:
	assert(manager != null, "MatchManager: manager is unassigned.")
	for top in manager.tops:
		scores[top] = 0
	manager.round_ended.connect(_on_round_ended)
	# Ready runs children first, so the manager has finished its own setup.
	call_deferred("_begin_round")


## Marker the manager checks for, so it knows not to start itself.
func register_manager() -> void:
	pass


func _begin_round() -> void:
	round_number += 1
	round_starting.emit(round_number, scores)

	if round_number == 1 and manager.intro != null:
		manager.play_intro(first_countdown)
		return

	if round_number > 1 and round_announce_pause > 0.0:
		await get_tree().create_timer(round_announce_pause, true, false, true).timeout
	manager.start_round(later_countdown)


func _on_round_ended(winners: Array[Top]) -> void:
	if _match_over:
		return
		
	print("round %d ended: %d winners, scores before: %s" % [
		round_number, winners.size(),
		str(scores.values())])
		
	
	for w in winners:
		if scores.has(w):
			scores[w] += 1
		
	print("  scores after: %s (target %d)" % [str(scores.values()), rounds_to_win])

	for top in scores:
		print("  checking %s: %d >= %d ? %s" % [
			top.display_name(), scores[top], rounds_to_win, scores[top] >= rounds_to_win])
		if scores[top] >= rounds_to_win:
			_match_over = true
			print("emitting match_complete from %s" % self)
			print("emitting to %d listeners" % match_complete.get_connections().size())
			match_complete.emit([top], scores)
			manager.freeze_tops(match_freeze_delay)
			return

	# Nobody there yet — but if no one can still reach the target, stop rather
	# than playing out rounds that cannot change the outcome.
	var remaining = (rounds_to_win * 2 - 1) - round_number
	var best = 0
	for top in scores:
		best = max(best, scores[top])
	if remaining <= 0:
		_match_over = true
		match_complete.emit(_leaders(), scores)
		return

	await get_tree().create_timer(between_rounds, true, false, true).timeout
	_begin_round()

func would_end_match(winners: Array[Top]) -> bool:
	for w in winners:
		if scores.has(w) and scores[w] + 1 >= rounds_to_win:
			return true
	return round_number >= rounds_to_win * 2 - 1

func _leaders() -> Array[Top]:
	var best = 0
	for top in scores:
		best = max(best, scores[top])
	var out: Array[Top] = []
	for top in scores:
		if scores[top] == best:
			out.append(top)
	return out
