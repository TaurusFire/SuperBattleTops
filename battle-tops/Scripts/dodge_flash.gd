class_name DodgeFlash
extends Node

## A brief emission spike on a top that slips a charge. The dodge mechanic
## currently reads as the top drifting sideways; the flash is what makes it
## legible as a deliberate evasion rather than an accident of movement.

@export var manager: GameManager

@export_group('Flash')
@export var flash_colour := Color(0.85, 0.95, 1.0)
## Peak emission energy. High enough to bloom against the arena.
@export var peak_energy := 2.5
@export var attack_time := 0.04
@export var decay_time := 0.22
@export var success_window := 0.1

# Per-top flash state, and the materials to drive.
var _flashing := {}
var _pending := {}

func _ready() -> void:
	assert(manager != null, "DodgeFlash: manager is unassigned.")
	for top in manager.tops:
		top.dodged.connect(_on_dodged)
	manager.collision_occurred.connect(_on_collision)
	set_process(false)


func _on_dodged(top: Top) -> void:
	# Stamped so a second dodge during the window supersedes the first rather
	# than both resolving.
	var stamp := Time.get_ticks_msec()
	_pending[top] = stamp

	await get_tree().create_timer(success_window, true, false, true).timeout

	if _pending.get(top, -1) != stamp:
		return
	_pending.erase(top)
	_flashing[top] = 0.0
	set_process(true)

## Any collision voids a pending flash for either participant — the slip
## didn't work, so it shouldn't be celebrated.
func _on_collision(a: Top, b: Top) -> void:
	_pending.erase(a)
	_pending.erase(b)

func _process(delta: float) -> void:
	if _flashing.is_empty():
		set_process(false)
		return

	var done := []
	for top in _flashing:
		var t: float = _flashing[top] + delta
		_flashing[top] = t

		var total := attack_time + decay_time
		if t >= total:
			_set_emission(top, 0.0)
			done.append(top)
			continue

		# Sharp rise, slower fall — the asymmetry is what makes it read as a
		# reaction rather than a pulse.
		var energy: float
		if t < attack_time:
			energy = peak_energy * (t / max(attack_time, 0.001))
		else:
			var d = (t - attack_time) / max(decay_time, 0.001)
			energy = peak_energy * (1.0 - d) * (1.0 - d)
		_set_emission(top, energy)

	for top in done:
		_flashing.erase(top)


## Drives every surface on the top, so the whole fighter lights rather than
## just its body or its rim.
func _set_emission(top: Top, energy: float) -> void:
	var mi := top.spin_visual
	if mi == null:
		return
	for i in mi.get_surface_override_material_count():
		var m := mi.get_surface_override_material(i) as StandardMaterial3D
		if m == null:
			continue
		m.emission_enabled = energy > 0.001
		m.emission = flash_colour
		m.emission_energy_multiplier = energy
