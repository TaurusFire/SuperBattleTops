class_name ArenaNameDisplay
extends BannerText

## Names the arena during the countdown. Positioned low in the frame so it sits
## clear of the countdown numbers and the gauges, and fades before the match
## starts — it's scene-setting, not something to read during a fight.

@export_group("Arena Name")
@export var manager: GameManager
@export var arena: Arena
@export var name_font_size := 60
## Fraction of the screen height the name sits at. Above 0.5 is below centre.
@export_range(0.0, 1.0) var vertical_position := 0.78
@export var name_top_colour := Color(0.96, 0.97, 1.0)
@export var name_bottom_colour := Color(0.62, 0.66, 0.78)
## Held for most of the countdown, then faded before "GO".
@export var name_hold := 2.2


func _ready() -> void:
	super()
	assert(manager != null, "ArenaNameDisplay: manager is unassigned.")
	assert(arena != null, "ArenaNameDisplay: arena is unassigned.")
	manager.match_started.connect(_on_match_started)
	if manager.phase == GameManager.Phase.COUNTDOWN:
		_show_name()
	else:
		manager.countdown_tick.connect(_on_first_tick)


func _on_first_tick(_count: int) -> void:
	# Only the first tick — after that the name is already up.
	manager.countdown_tick.disconnect(_on_first_tick)
	_show_name()


func _show_name() -> void:
	set_colours(name_top_colour, name_bottom_colour)
	show_text(arena.display_name.to_upper(), name_hold, 1.0, name_font_size)

func dismiss() -> void:
	_active_hold = min(_active_hold, _timer + fade_time)
	
func _on_match_started() -> void:
	# Clear it whatever the hold had left: the fight shouldn't start with
	# scene-setting text still on screen.
	dismiss()
