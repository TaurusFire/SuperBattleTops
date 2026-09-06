class_name FinishDisplay
extends BannerText

## Announces *how* the match ended, ahead of who won. The distinction matters
## for the clip: a knockout and a spin-out are different endings, and naming
## which one happened lands harder than going straight to the winner.

signal finish_shown

@export_group("Finish")
@export var manager: GameManager
@export var ko_text := "K.O.!"
@export var game_text := "GAME!"
@export var finish_hold := 1.4
@export var finish_font_size := 150
@export var ko_top_colour := Color(1.0, 0.85, 0.25)
@export var ko_bottom_colour := Color(0.92, 0.28, 0.12)
@export var game_top_colour := Color(0.95, 0.96, 1.0)
@export var game_bottom_colour := Color(0.55, 0.60, 0.72)

var _announced := false


func _ready() -> void:
	super()
	assert(manager != null, "FinishDisplay: manager is unassigned.")
	for top in manager.tops:
		top.knocked_out.connect(_on_knocked_out)
		top.stopped.connect(_on_stopped)


func _on_knocked_out(_top: Top) -> void:
	if not _is_final():
		return
	_announce(ko_text, ko_top_colour, ko_bottom_colour)


func _on_stopped(top: Top) -> void:
	# entered_dying also fires for knockouts, which have their own call.
	if top.current_state == Top.State.KNOCKED_OUT:
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
	set_colours(top_col, bottom_col)
	show_text(text, finish_hold, 1.0, finish_font_size)

	await get_tree().create_timer(finish_hold, true, false, true).timeout
	finish_shown.emit()
