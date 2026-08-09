class_name ResultDisplay
extends BannerText

@export_group("Result")
@export var manager: GameManager
## Seconds to wait after the match resolves before the banner appears, so the
## topple has time to play out.
@export var result_delay := 0.4
@export var result_hold := 1.5
@export var result_font_size := 96
@export var draw_text := "DRAW"
@export var no_contest_text := "NO CONTEST"
## Gradient for a draw — neutral grey, since no fighter owns the outcome.
@export var draw_top_colour := Color(0.423, 0.45, 0.537, 1.0)
@export var draw_bottom_colour := Color(0.779, 0.793, 0.82, 1.0)

func _ready() -> void:
	super()
	assert(manager != null, "ResultDisplay needs the manager assigned.")
	manager.match_ended.connect(_on_match_ended)


func _on_match_ended(winners: Array[Top]) -> void:
	var text: String
	if winners.is_empty():
		text = no_contest_text
		set_colours(top_colour, bottom_colour)
	elif winners.size() == 1:
		var w := winners[0]
		text = "%s WINS" % w.display_name().to_upper()
		# The winner's own colours, so the banner belongs to that fighter.
		var base := w.stats.name_colour
		var second := w.stats.name_colour_secondary
		if second.a > 0.001:
			set_colours(base, second)
		else:
			set_colours(base, base)
	else:
		text = draw_text
		set_colours(draw_top_colour, draw_bottom_colour)
	if winners.is_empty():
		text = no_contest_text
		set_colours(draw_top_colour, draw_bottom_colour)

	if result_delay > 0.0:
		await get_tree().create_timer(result_delay, true, false, true).timeout

	show_text(text, result_hold, 1.0, result_font_size)
