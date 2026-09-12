class_name FinishDisplay
extends BannerText

## Announces *how* the match ended, ahead of who won. The distinction matters
## for the clip: a knockout and a spin-out are different endings, and naming
## which one happened lands harder than going straight to the winner.

@export_group("Finish")
@export var match_manager: MatchManager
@export var manager: GameManager
@export var ko_text := "K.O.!"
@export var game_text := "GAME!"
@export var finish_hold := 1.5
@export var finish_font_size := 150
@export var ko_top_colour := Color(1.0, 0.85, 0.25)
@export var ko_bottom_colour := Color(0.92, 0.28, 0.12)
@export var game_top_colour := Color(0.95, 0.96, 1.0)
@export var game_bottom_colour := Color(0.55, 0.60, 0.72)

var _announced := false
var _knocked_out_tops := {}


func _ready() -> void:
	super()
	assert(manager != null, "FinishDisplay: manager is unassigned.")
	for top in manager.tops:
		top.knocked_out.connect(_on_knocked_out)
		top.stopped.connect(_on_stopped)
	if match_manager != null:
		match_manager.round_starting.connect(_on_round_starting)

	else:
		print("FD: match_manager is null")


func _on_round_starting(_round_number: int, _scores: Dictionary) -> void:
	_announced = false
	_knocked_out_tops.clear()

func _on_knocked_out(top: Top) -> void:
	print("FD knocked_out %s: is_final=%s announced=%s" % [
		top.display_name(), _is_final(), _announced])
	_knocked_out_tops[top] = true
	if not _is_final():
		return
	_announce(ko_text, ko_top_colour, ko_bottom_colour)


func _on_stopped(top: Top) -> void:
	# A knockout announces itself as it clears the rim. By the time it stops,
	# its state is STOPPED like any other, so the state alone can't tell them
	# apart — hence the record.
	print("FD stopped %s (state %d): knocked=%s is_final=%s announced=%s" % [
		top.display_name(), top.current_state,
		_knocked_out_tops.has(top), _is_final(), _announced])
	if _knocked_out_tops.has(top):
		return
	if not _is_final():
		return
	_announce(game_text, game_top_colour, game_bottom_colour)


## True when at most one top is still fighting — so this is the ending, not
## just an elimination partway through a three-way.
func _is_final() -> bool:
	var alive = manager.tops.filter(func(t):
		return t.current_state not in [Top.State.STOPPED, Top.State.KNOCKED_OUT])
	return alive.size() <= 1


func _announce(text: String, top_col: Color, bottom_col: Color) -> void:
	if _announced:
		return
	_announced = true
	print("[%d] FINISH banner shown: %s" % [Time.get_ticks_msec(), text])
	set_colours(top_col, bottom_col)
	show_text(text, finish_hold, 1.0, finish_font_size)
