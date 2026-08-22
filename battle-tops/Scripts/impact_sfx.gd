class_name ImpactSfx
extends Node

## Impact audio for clashes and wall hits. Tiered by force rather than
## triggered per event, so the mix has the same hierarchy the visuals do — a
## glancing tap and a kamikaze strike shouldn't sound alike.

@export var manager: GameManager

@export_group('Clash Sounds')
## Ordered from weakest to strongest. The hit's strength picks a position in
## this list rather than a bucket, so the sound scales with the force
## continuously — nine samples give a much finer gradient than three tiers of
## interchangeable variants.
@export var clash_sounds: Array[AudioStream] = []
## Strength that maps to the last entry. Anything above uses it.
@export var clash_reference := 1.9
## How far either side of the ideal sample the pick may stray, so identical
## hits don't always sound identical. In entries.
@export var clash_spread := 0
@export var knockback_weight := 0.65

@export_group('References')
@export var knockback_reference := 50.0
@export var damage_reference := 110.0
@export_range(0.3, 2.0) var clash_curve := 0.45

@export_group('Wall')
## Ordered weakest to strongest, same as the clash set.
@export var wall_sounds: Array[AudioStream] = []
## Outward speed that maps to the last entry.
@export var wall_reference := 1.2
@export var wall_volume_min_db := -30.0
@export var wall_volume_max_db := -20.0

@export_group('Mix')
@export var clash_volume_min_db := -20.0
@export var clash_volume_max_db := -8.0
## Random pitch spread, so repeated hits don't sound mechanical.
@export var pitch_variance := 0.3
## Players in the pool. Impacts overlap constantly, so a single player would
## cut each hit off with the next.
@export var pool_size := 5

var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	assert(manager != null, "ImpactSfx: manager is unassigned.")
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_pool.append(p)

	manager.collision_occurred.connect(_on_clash)
	for top in manager.tops:
		top.wall_hit.connect(_on_wall_hit)


func _on_clash(a: Top, b: Top) -> void:
	if clash_sounds.is_empty():
		return
	

	var kb = pow(max(a.last_knockback_dealt, b.last_knockback_dealt) / knockback_reference, 0.6)
	var dmg = max(a.last_damage_dealt, b.last_damage_dealt) / damage_reference
	var strength = kb * knockback_weight + dmg * (1.0 - knockback_weight)
	

	
	var t = clamp(strength / clash_reference, 0.0, 1.0)
	var ideal = pow(t, clash_curve) * float(clash_sounds.size() - 1)

	# Taper the spread toward the ends of the range: an exceptional hit should
	# always get the heaviest sample rather than sometimes settling for the
	# one below it.
	var edge = min(ideal, float(clash_sounds.size() - 1) - ideal)
	var spread = clash_spread * clamp(edge, 0.0, 1.0)
	var pick = int(round(ideal + randf_range(-spread, spread)))
	
	pick = clamp(pick, 0, clash_sounds.size() - 1)

	print("clash sfx: strength=%.2f pick=%d of %d, kb=%.1f dmg=%.1f" % [
		strength, pick, clash_sounds.size(),
		max(a.last_knockback_dealt, b.last_knockback_dealt),
		max(a.last_damage_dealt, b.last_damage_dealt)])
	
	# Volume follows the same curve, so the mix reinforces the sample choice
	# rather than flattening it.
	var db = lerpf(clash_volume_min_db, clash_volume_max_db, t)

	_play_one(clash_sounds[pick], db)


func _on_wall_hit(_top: Top, force: float) -> void:
	if wall_sounds.is_empty():
		return
	var t = clamp(force / wall_reference, 0.0, 1.0)
	var pick = int(round(t * float(wall_sounds.size() - 1)))
	_play_one(wall_sounds[pick], lerpf(wall_volume_min_db, wall_volume_max_db, t))


func _play_one(stream: AudioStream, db: float) -> void:
	if stream == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	p.play()
