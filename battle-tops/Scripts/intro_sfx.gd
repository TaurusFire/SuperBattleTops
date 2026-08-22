class_name IntroSfx
extends Node

## Audio for the fly-in. The whoosh fires as each top begins its approach
## rather than at the apex, so the sound peaks with the movement rather than
## arriving after it has stopped.

@export var intro: IntroSequence

@export_group('Clips')
## Played as a top swings in toward the camera.
@export var whoosh: Array[AudioStream] = []
## Optional: a softer cue as it departs for its mark.
@export var departure: Array[AudioStream] = []

@export_group('Mix')
@export var whoosh_volume_db := -3.0
@export var departure_volume_db := -9.0
@export var pitch_variance := 0.08
@export var pool_size := 4

var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	assert(intro != null, "IntroSfx: intro is unassigned.")
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_pool.append(p)

	intro.top_approaching.connect(_on_approaching)
	intro.top_departed.connect(_on_departed)


func _on_approaching(_top: Top, _index: int) -> void:
	_play(whoosh, whoosh_volume_db)


func _on_departed(_top: Top, _index: int) -> void:
	_play(departure, departure_volume_db)


func _play(set: Array[AudioStream], db: float) -> void:
	if set.is_empty():
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = set[randi() % set.size()]
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	p.play()
