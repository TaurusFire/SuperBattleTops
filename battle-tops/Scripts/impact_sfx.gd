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
@export_range(0.3, 2.0) var clash_curve := 0.5

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

@export_group('Knockout')
## Plays when a hit is projected to send a top out. A low sustained note under
## the slowdown, so the moment has weight rather than just being slower.
@export var doom_sting: AudioStream
@export var doom_volume_db := -8.0
## Fade at the end, so it doesn't cut abruptly when the slowdown lifts.
@export var doom_fade := 0.2
## How long it sounds. Match the manager's deciding_blow_time, or the audio
## and the slowdown end at different moments.
@export var doom_duration := 1.2
## Announced when a knockout ends the match. Only for the deciding one — a
## call on every knockout in a three-way would flatten the moment.
@export var ko_call: AudioStream
@export var ko_call_volume_db := -20
## Delay so the call lands as the top clears the rim rather than racing it.
@export var ko_call_delay := 0.00
@export var voice_pitch := 1
## Rings under the K.O. call. A bell has a long tail, so it needs its own
## player — sharing with the voice would have each cut the other off.
@export var finish_bell: AudioStream
@export var finish_bell_volume_db := -3.0
## Delay relative to the call. Slightly ahead reads as the bell triggering the
## announcement rather than echoing it.
@export var finish_bell_delay := 0.0

@export_group('Finish')
## Called when the last top spins out rather than being knocked out.
@export var game_call: AudioStream
@export var game_call_volume_db := 0.0
@export var game_call_delay := 0.25

var _game_player: AudioStreamPlayer
var _bell_player: AudioStreamPlayer
var _ko_player: AudioStreamPlayer
var _doom_player: AudioStreamPlayer
var _doom_tween: Tween
var _finish_called := false

func _ready() -> void:
	assert(manager != null, "ImpactSfx: manager is unassigned.")
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_pool.append(p)
	# Its own player rather than the pool: the sting is sustained, and a clash
	# landing a moment later would claim a pooled player and cut it off.
	_doom_player = AudioStreamPlayer.new()
	_doom_player.bus = bus
	add_child(_doom_player)
	
	manager.collision_occurred.connect(_on_clash)
	manager.knockout_projected.connect(_on_knockout_projected)

	_ko_player = AudioStreamPlayer.new()
	_ko_player.bus = bus
	add_child(_ko_player)

	_game_player = AudioStreamPlayer.new()
	_game_player.bus = bus
	add_child(_game_player)
	
	_bell_player = AudioStreamPlayer.new()
	_bell_player.bus = bus
	add_child(_bell_player)
	
	for top in manager.tops:
		top.wall_hit.connect(_on_wall_hit)
		top.knocked_out.connect(_on_knocked_out)
		top.stopped.connect(_on_stopped)

func _on_stopped(top: Top) -> void:
	# entered_dying also fires for knockouts, which have their own call.
	if _finish_called:
		return
	if top.current_state == Top.State.KNOCKED_OUT:
		return
	var still_in = manager.tops.filter(func(t):
		return t.current_state == Top.State.ACTIVE)
	if still_in.size() > 1:
		return

	_finish_called = true
	_ring_bell()
	
	if game_call == null:
		return
	if game_call_delay > 0.0:
		await get_tree().create_timer(game_call_delay, true, false, true).timeout
	_game_player.stream = game_call
	_game_player.volume_db = game_call_volume_db
	_game_player.play()

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

	#print("clash sfx: strength=%.2f pick=%d of %d, kb=%.1f dmg=%.1f" % [
		#strength, pick, clash_sounds.size(),
		#max(a.last_knockback_dealt, b.last_knockback_dealt),
		#max(a.last_damage_dealt, b.last_damage_dealt)])
	
	# Volume follows the same curve, so the mix reinforces the sample choice
	# rather than flattening it.
	var db = lerpf(clash_volume_min_db, clash_volume_max_db, t)

	_play_one(clash_sounds[pick], db)

func _on_knocked_out(_top: Top) -> void:
	if _finish_called:
		return

	# Only when it settles the match: everyone else is already out or on their
	# way, so this knockout is the one that ends it.
	var still_in = manager.tops.filter(func(t):
		return t.current_state == Top.State.ACTIVE)
	if still_in.size() > 1:
		return
	
	_finish_called = true
	_ring_bell()
		
	if ko_call == null:
		return
	if ko_call_delay > 0.0:
		await get_tree().create_timer(ko_call_delay, true, false, true).timeout
	_ko_player.stream = ko_call
	_ko_player.pitch_scale = voice_pitch
	_ko_player.volume_db = ko_call_volume_db
	_ko_player.play()

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
	
func _on_knockout_projected(_top: Top, _attacker: Top) -> void:
	if doom_sting == null:
		return
	
	for t in manager.tops:
		if t.current_state == Top.State.KNOCKED_OUT:
			return
	if _doom_tween != null and _doom_tween.is_valid():
		_doom_tween.kill()
	_doom_player.stream = doom_sting
	_doom_player.volume_db = doom_volume_db
	_doom_player.play()

	var hold = max(doom_duration - doom_fade, 0.0)
	if hold > 0.0:
		await get_tree().create_timer(hold, true, false, true).timeout
	

	for t in manager.tops:
		if t.current_state in [Top.State.KNOCKED_OUT, Top.State.DYING]:
			return
	if manager.phase in [GameManager.Phase.ENDING, GameManager.Phase.ENDED]:
		return

	_doom_tween = create_tween()
	_doom_tween.tween_property(_doom_player, "volume_db", -60.0, doom_fade)
	await _doom_tween.finished
	_doom_player.stop()
	_doom_player.volume_db = doom_volume_db
	
func _ring_bell() -> void:
	if finish_bell == null:
		return
	_bell_player.stream = finish_bell
	_bell_player.volume_db = finish_bell_volume_db
	_bell_player.play()
