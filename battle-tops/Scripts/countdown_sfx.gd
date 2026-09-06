class_name CountdownSfx
extends Node

## Plays the spoken countdown. Triggered by the manager's signals rather than
## played as one track, so each number lands on the same frame as its banner
## text — a pre-mixed clip would drift against the animation.

@export var manager: GameManager

@export_group('Clips')
@export var number_clips: Array[AudioStream] = []
## Spoken numbers, same indexing. Played over the beeps rather than instead of
## them, so the tone carries the rhythm and the voice the character.
@export var number_voices: Array[AudioStream] = []
@export var go_clip: AudioStream
@export var go_beep: AudioStream
@export var beep_volume_db := -6.0
@export var go_beep_volume_db := -4.0
var _player: AudioStreamPlayer
var _beep_player: AudioStreamPlayer


@export_group('Mix')
@export var volume_db := -5.0
## Slight delay so the voice lands with the text's punch rather than ahead of
## it — the banner scales in over a few frames.
@export var lead_in := 0.04
## Pitch multiplier on the voice clips. Above 1 raises and shortens, below
## lowers and lengthens — Godot doesn't separate the two, so large shifts
## change the delivery's pace as well as its tone.
@export_range(0.5, 2.0) var count_pitch := 1
@export_range(0.5, 2.0) var go_pitch := 1


func _ready() -> void:
	assert(manager != null, "CountdownSfx: manager is unassigned.")
	var bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"

	_player = AudioStreamPlayer.new()
	_player.bus = bus
	_player.volume_db = volume_db
	add_child(_player)

	# Separate player: the voice and the tone sound together, so sharing one
	# would mean the second call cutting off the first.
	_beep_player = AudioStreamPlayer.new()
	_beep_player.bus = bus
	add_child(_beep_player)

	manager.countdown_tick.connect(_on_tick)
	manager.match_started.connect(_on_started)


func _on_tick(count: int) -> void:
	if count >= 0 and count < number_clips.size() and number_clips[count] != null:
		_beep_player.stream = number_clips[count]
		_beep_player.volume_db = beep_volume_db
		_beep_player.play()

	if count >= 0 and count < number_voices.size():
		_speak(number_voices[count], 'count')


func _on_started() -> void:
	if go_beep != null:
		_beep_player.stream = go_beep
		_beep_player.volume_db = go_beep_volume_db
		_beep_player.play()
	_speak(go_clip, "go")


func _speak(clip: AudioStream, purpose: String) -> void:
	if clip == null:
		return
	if lead_in > 0.0:
		await get_tree().create_timer(lead_in, true, false, true).timeout
	_player.stream = clip
	if purpose == 'count':
		_player.pitch_scale = count_pitch
	else:
		_player.pitch_scale = go_pitch
	_player.play()
