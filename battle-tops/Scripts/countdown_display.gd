class_name CountdownDisplay
extends BannerText

@export_group("Countdown")
@export var manager: GameManager
@export var go_text := "GO!"
@export var hold := 0.62
@export var go_hold := 1.1
@export var go_scale := 1.15


func _ready() -> void:
	super()
	assert(manager != null, "CountdownDisplay needs the manager assigned.")
	manager.countdown_tick.connect(_on_tick)
	manager.match_started.connect(_on_match_started)
	if manager.phase == GameManager.Phase.COUNTDOWN:
		show_text(str(int(ceil(manager.time_remaining))), hold)


func _on_tick(count: int) -> void:
	show_text(str(count), hold)


func _on_match_started() -> void:
	show_text(go_text, go_hold, go_scale)
