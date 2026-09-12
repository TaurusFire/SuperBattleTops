class_name RoundDisplay
extends BannerText

## Announces each round. Deliberately brief — the round number is orientation,
## not a moment, and the between-round gap is where a viewer scrolls away.

@export_group("Round")
@export var match_manager: MatchManager
@export var round_font_size := 130
@export var round_hold := 1.0
## Shown instead of the number when it's the decider. A "FINAL ROUND" card
## does more for retention than "ROUND 3" — it tells the viewer this one
## settles it.
@export var final_round_text := "FINAL ROUND"
@export var show_final_text := true
## Skipped for round one, which already has the intro and countdown.
@export var announce_first_round := true

@export_group("Round Colours")
@export var round_top_colour := Color(0.96, 0.97, 1.0)
@export var round_bottom_colour := Color(0.58, 0.63, 0.76)
@export var final_top_colour := Color(1.0, 0.88, 0.35)
@export var final_bottom_colour := Color(0.94, 0.36, 0.14)


func _ready() -> void:
	super()
	assert(match_manager != null, "RoundDisplay: match_manager is unassigned.")
	match_manager.round_starting.connect(_on_round_starting)


func _on_round_starting(round_number: int, scores: Dictionary) -> void:
	if round_number == 1 and not announce_first_round:
		return
	print("[%d] ROUND banner shown: round %d" % [Time.get_ticks_msec(), round_number])
	if show_final_text and _is_decider(scores):
		set_colours(final_top_colour, final_bottom_colour)
		show_text(final_round_text, round_hold, 1.0, round_font_size)
	else:
		set_colours(round_top_colour, round_bottom_colour)
		show_text("ROUND %d" % round_number, round_hold, 1.0, round_font_size)

func _is_decider(scores: Dictionary) -> bool:
	var max_rounds = match_manager.rounds_to_win * 2 - 1
	if match_manager.round_number >= max_rounds:
		return true
	for top in scores:
		if scores[top] < match_manager.rounds_to_win - 1:
			return false
	return true
