class_name ResultDisplay
extends BannerText

signal result_dismissed

@export_group("Result")
@export var match_manager: MatchManager
@export var manager: GameManager
## Seconds to wait after the match resolves before the banner appears, so the
## topple has time to play out.
@export var result_hold := 2.0
@export var result_font_size := 96
@export var draw_text := "DRAW"
@export var no_contest_text := "NO CONTEST"
## Gradient for a draw — neutral grey, since no fighter owns the outcome.
@export var draw_top_colour := Color(0.423, 0.45, 0.537, 1.0)
@export var draw_bottom_colour := Color(0.779, 0.793, 0.82, 1.0)

@export var finish_display: FinishDisplay
## Extra pause after the finish banner clears, before the winner appears.

var _pending_winners: Array[Top] = []


func _ready() -> void:
	super()
	assert(match_manager != null, "ResultDisplay: match_manager is unassigned.")
	match_manager.match_complete.connect(_on_match_complete)


func _on_match_complete(winners: Array[Top], _scores: Dictionary) -> void:
	_pending_winners = winners
	_show_result()

func _show_result() -> void:
	var winners = _pending_winners
	_pending_winners = []

	var text: String
	if winners.is_empty():
		text = no_contest_text
		set_colours(draw_top_colour, draw_bottom_colour)
	elif winners.size() == 1:
		var w = winners[0]
		text = "%s WINS" % w.display_name().to_upper()
		var base = w.stats.name_colour
		var second = w.stats.name_colour_secondary
		set_colours(base, second if second.a > 0.001 else base)
	else:
		text = draw_text
		set_colours(draw_top_colour, draw_bottom_colour)

	# A top still dying means the finish banner hasn't announced yet: it fires
	# when the loser finishes toppling or falls out, which lags the round
	# resolving by over a second. Checking `visible` alone would find nothing
	# up and let the result through first.
	if manager != null and manager.has_dying_tops():
		await manager.round_settled
		# Resuming from an await runs inside the emit, before the remaining
		# handlers of that signal — including the one that shows the banner.
		await get_tree().process_frame
	else:
		await get_tree().process_frame

	if finish_display != null and finish_display.visible:
		await finish_display.dismissed

	show_text(text, result_hold, 1.0, result_font_size)
	await get_tree().create_timer(result_hold, true, false, true).timeout
	result_dismissed.emit()
