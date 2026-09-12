class_name SurfaceSfx
extends Node

## The sound of tops running on the arena floor. One looping player per
## fighter, with level and pitch following its speed — a constant hum would
## read as ambience rather than as motion.

@export var manager: GameManager
## Must be an imported audio file with Loop enabled in its Import tab.
@export var surface_loop: AudioStream
## Speed at which the sound reaches full volume.
@export var speed_reference := 0.5
@export var quiet_db := -40.0
@export var loud_db := -10.0
## How much the pitch rises with speed.
@export var pitch_range := 0.35
## How quickly the level follows speed changes. Low enough that a single
## knockback doesn't produce an audible blip.
@export var responsiveness := 6.0

var _players := {}
var _levels := {}


func _ready() -> void:
	assert(manager != null, "SurfaceSfx: manager is unassigned.")
	if surface_loop == null:
		return
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for top in manager.tops:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.stream = surface_loop
		p.volume_db = -60.0
		add_child(p)
		p.play()
		_players[top] = p
		_levels[top] = 0.0


func _process(delta: float) -> void:
	for top in _players:
		var p: AudioStreamPlayer = _players[top]
		# Only a grounded, fighting top is in contact with the floor.
		var target := 0.0
		if top.current_state == Top.State.ACTIVE and not top._airborne:
			target = clamp(top._velocity.length() / max(speed_reference, 0.001), 0.0, 1.0)

		_levels[top] = lerpf(_levels[top], target, clamp(responsiveness * delta, 0.0, 1.0))
		var level: float = _levels[top]

		if level < 0.01:
			p.volume_db = -60.0
			continue
		p.volume_db = lerpf(quiet_db, loud_db, level)
		p.pitch_scale = 1.0 + pitch_range * (level - 0.5)
