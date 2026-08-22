class_name CountdownSfx
extends Node

## Plays the spoken countdown. Triggered by the manager's signals rather than
## played as one track, so each number lands on the same frame as its banner
## text — a pre-mixed clip would drift against the animation.

@export var manager: GameManager

@export_group('Clips')
## Indexed by the count, so entry 0 is unused, 1 is "one", 2 is "two", and so
## on. Sized to whatever your countdown starts at.
@export var number_clips: Array[AudioStream] = []
@export var go_clip: AudioStream

@export_group('Mix')
@export var volume_db := -2.0
## Slight delay so the voice lands with the text's punch rather than ahead of
## it — the banner scales in over a few frames.
@export var lead_in := 0.04

var _player: AudioStreamPlayer


func _ready() -> void:
	assert(manager != null, "CountdownSfx: manager is unassigned.")
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_player.volume_db = volume_db
	add_child(_player)

	manager.countdown_tick.connect(_on_tick)
	manager.match_started.connect(_on_started)


func _on_tick(count: int) -> void:
	if count < 0 or count >= number_clips.size():
		return
	_speak(number_clips[count])


func _on_started() -> void:
	_speak(go_clip)


func _speak(clip: AudioStream) -> void:
	if clip == null:
		return
	if lead_in > 0.0:
		await get_tree().create_timer(lead_in, true, false, true).timeout
	_player.stream = clip
	_player.play()
