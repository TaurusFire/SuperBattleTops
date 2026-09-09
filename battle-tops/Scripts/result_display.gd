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
	# ... unchanged branch building text and colours ...

	# One gate, on the banner's own signal. A frame's wait first, because
	# match_complete and the finish announcement come from the same round
	# resolution and the banner may not have claimed the screen yet.
	await get_tree().process_frame
	if finish_display != null and finish_display.visible:
		await finish_display.dismissed
	print("[%d] showing result: '%s' visible=%s size=%s" % [
		Time.get_ticks_msec(), text, visible, size])
	show_text(text, result_hold, 1.0, result_font_size)
	await get_tree().create_timer(result_hold, true, false, true).timeout
	result_dismissed.emit()
