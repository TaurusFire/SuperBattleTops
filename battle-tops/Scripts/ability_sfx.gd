class_name AbilitySfx
extends Node

## Plays the audio cues for ability moments. Listens to the tops' signals
## rather than being driven by the abilities, so a new ability only needs to
## emit to get a sound.

@export var manager: GameManager

@export_group('Lock-On')
## Plays the instant the crosshair appears.
@export var lock_click: AudioStream
@export var lock_click_volume_db := -6.0
## Follows shortly after, as the charge builds.
@export var lock_buzzer: AudioStream
@export var lock_delay := 0.95
@export var lock_volume_db := -6.0
## How long the buzzer sounds. Zero plays the whole file.
@export var lock_buzzer_duration := 1.0
## Fade at the end, in seconds. Cutting a tone dead produces an audible click,
## so even a very short ramp is worth having.
@export var lock_buzzer_fade := 0.04

var _click_player: AudioStreamPlayer
var _buzz_player: AudioStreamPlayer


func _ready() -> void:
	assert(manager != null, "AbilitySfx: manager is unassigned.")
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_click_player = AudioStreamPlayer.new()
	_click_player.bus = bus
	add_child(_click_player)
	_buzz_player = AudioStreamPlayer.new()
	_buzz_player.bus = bus
	add_child(_buzz_player)

	for top in manager.tops:
		top.target_locked.connect(_on_locked)


func _on_locked(_top: Top, _target: Top, _tint: Color) -> void:
	if lock_click != null:
		_click_player.stream = lock_click
		_click_player.volume_db = lock_click_volume_db
		_click_player.play()

	if lock_buzzer == null:
		return
	if lock_delay > 0.0:
		# Unscaled, so hitstop or the ending slow-mo don't stretch the cue.
		await get_tree().create_timer(lock_delay, true, false, true).timeout
		
	if _top.current_state != Top.State.ACTIVE:
		return
		
	_buzz_player.stream = lock_buzzer
	_buzz_player.volume_db = lock_volume_db
	_buzz_player.play()

	if lock_buzzer_duration <= 0.0:
		return

	var hold = max(lock_buzzer_duration - lock_buzzer_fade, 0.0)
	if hold > 0.0:
		await get_tree().create_timer(hold, true, false, true).timeout

	if lock_buzzer_fade > 0.0:
		var tween = create_tween()
		# -60 dB is effectively silent; ramping to it avoids the click that a
		# hard stop on a sustained tone produces.
		tween.tween_property(_buzz_player, "volume_db", -60.0, lock_buzzer_fade)
		await tween.finished

	_buzz_player.stop()
	_buzz_player.volume_db = lock_volume_db
