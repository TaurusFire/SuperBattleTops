class_name RoundResultDisplay
extends BannerText

## Names who took a round. Deliberately lighter than the match result — this
## is a scoreline update, not the payoff, and dwelling on it costs the gap
## where a viewer scrolls away.

@export var manager: GameManager
@export var match_manager: MatchManager
@export var round_result_hold := 1.2
@export var round_result_font_size := 84


func _ready() -> void:
	super()
	manager.round_ended.connect(_on_round_ended)


func _on_round_ended(winners: Array[Top]) -> void:
	# The final round's result is the match result, which gets its own banner.
	if match_manager != null and match_manager.would_end_match(winners):
		return
	if winners.size() != 1:
		return
	var w = winners[0]
	var base = w.stats.name_colour
	var second = w.stats.name_colour_secondary
	set_colours(base, second if second.a > 0.001 else base)
	show_text("%s TAKES IT" % w.display_name().to_upper(),
			  round_result_hold, 1.0, round_result_font_size)
