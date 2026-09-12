class_name RoundSfx
extends Node

## Audio for the round transitions: a gong as each round is announced, and a
## voice naming it. Separate from the finish sounds in ImpactSfx, which mark
## the end of a round rather than the start of one.

@export var match_manager: MatchManager

@export_group('Gong')
## Struck as the round banner appears.
@export var round_gong: AudioStream
@export var gong_volume_db := -3.0

@export_group('Voice')
## Indexed by round number: slot 0 unused, 1 is "round one", and so on.
@export var round_voices: Array[AudioStream] = []
## Announced instead of the number when it's the decider, if set.
@export var final_round_voice: AudioStream
@export var voice_volume_db := -1.0
## Delay after the gong, so the two read as a signal and an announcement
## rather than as one muddled sound.
@export var voice_delay := 0.35

var _gong_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer


func _ready() -> void:
	assert(match_manager != null, "RoundSfx: match_manager is unassigned.")
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"

	_gong_player = AudioStreamPlayer.new()
	_gong_player.bus = bus
	add_child(_gong_player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = bus
	add_child(_voice_player)

	match_manager.round_starting.connect(_on_round_starting)


func _on_round_starting(round_number: int, scores: Dictionary) -> void:
	if round_gong != null:
		_gong_player.stream = round_gong
		_gong_player.volume_db = gong_volume_db
		_gong_player.play()

	var clip := _voice_for(round_number, scores)
	if clip == null:
		return
	if voice_delay > 0.0:
		await get_tree().create_timer(voice_delay, true, false, true).timeout
	_voice_player.stream = clip
	_voice_player.volume_db = voice_volume_db
	_voice_player.play()


## The decider gets its own line if one is recorded, matching the banner —
## "final round" carries more than a number does.
func _voice_for(round_number: int, scores: Dictionary) -> AudioStream:
	if final_round_voice != null and _is_decider(scores, round_number):
		return final_round_voice
	if round_number >= 0 and round_number < round_voices.size():
		return round_voices[round_number]
	return null


func _is_decider(scores: Dictionary, round_number: int) -> bool:
	var max_rounds = match_manager.rounds_to_win * 2 - 1
	if round_number >= max_rounds:
		return true
	for top in scores:
		if scores[top] < match_manager.rounds_to_win - 1:
			return false
	return true
