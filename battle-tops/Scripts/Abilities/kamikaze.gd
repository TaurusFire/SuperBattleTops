class_name KamikazeAbility
extends Ability

## At a threshold RPM the top stops fighting, holds for a beat, then hurls
## itself at the nearest opponent at full power. It expires when the window
## closes whether or not the strike landed — a last gamble, not a free hit.

enum Phase { DORMANT, TELEGRAPH, CHARGING, SPENDING }

@export var trigger_rpm := 500.0
## Speed multiplier during the charge, against the top's own move_speed.
@export var charge_speed := 2
## Seconds of flashing before the charge, so the viewer registers it coming.
@export var telegraph_time := 1.5
## Seconds the charge lasts before the top expires regardless of outcome.
@export var window := 0.3
## How hard it tracks. High, so it doesn't miss through slow turning.
@export var agility := 15
@export var strike_power := 5
@export var strike_vertical_bias := 2
## Seconds between the strike landing and the top giving up its remaining RPM.
## Keeps it ACTIVE through the collision so hitstop and sparks resolve, and
## gives the moment room to land before the fall begins.
@export var spend_delay := 1.25
## Tint for the targeting reticle.
@export var marker_colour := Color(0.72, 0.32, 0.95)

# Per-top state, keyed by instance — an ability resource is shared between
# fighters that use it, so it cannot hold state in plain fields.
var _phase := {}
var _timer := {}
var _target := {}


func phase_of(top: Top) -> Phase:
	return _phase.get(top, Phase.DORMANT)


func target_of(top: Top) -> Top:
	return _target.get(top, null)


func tick(top: Top, delta: float) -> void:
	var p: Phase = phase_of(top)

	if p == Phase.DORMANT:
		if top.current_rpm <= trigger_rpm:
			_begin(top)
		return

	_timer[top] = _timer.get(top, 0.0) - delta
	
	if p == Phase.SPENDING:
		if _timer[top] <= 0.0:
			_expire(top)
		return

	if p == Phase.TELEGRAPH:
		if _timer[top] <= 0.0:
			_phase[top] = Phase.CHARGING
			_timer[top] = window
		return

	# Charging: expire when the window closes or the target is gone.
	var t: Top = _target.get(top, null)
	if _timer[top] <= 0.0 or t == null or t.current_state != Top.State.ACTIVE:
		_expire(top)


func controls_movement(top: Top) -> bool:
	return phase_of(top) != Phase.DORMANT


func attack_rpm(top: Top) -> float:
	# The whole point: a spent top still lands one devastating blow.
	if phase_of(top) == Phase.CHARGING:
		return top.initial_rpm
	return top.current_rpm


func intercept_death(top: Top) -> bool:
	return phase_of(top) != Phase.DORMANT


## Called by the top when its kamikaze strike connects.
func on_hit_landed(top: Top) -> void:
	if phase_of(top) != Phase.CHARGING:
		return
	# Don't die yet: the manager is still resolving this collision, and the
	# hit reads better if the fall comes a beat after the impact.
	_phase[top] = Phase.SPENDING
	_timer[top] = spend_delay


func _begin(top: Top) -> void:
	var t := top._nearest_opponent()
	if t == null:
		print("[%s] kamikaze: no target, dying normally" % top.display_name())
		return
	_target[top] = t
	_phase[top] = Phase.TELEGRAPH
	_timer[top] = telegraph_time
	top._velocity = Vector2.ZERO    # the pause makes the charge read as sudden
	top.target_locked.emit(top, t, marker_colour)
	top.ability_triggered.emit(top, self)


func _expire(top: Top) -> void:
	# Spent, win or lose: the strike costs everything that was left.
	top.current_rpm = 0.0
	top.target_released.emit(top)
	_phase[top] = Phase.DORMANT
	_target.erase(top)
	_timer.erase(top)
	top._enter_dying()

func strike_multiplier(top: Top) -> float:
	return strike_power if phase_of(top) == Phase.CHARGING else 1.0
	
func vertical_bias(top: Top) -> float:
	return strike_vertical_bias if phase_of(top) == Phase.CHARGING else 1.0
	
func gauge_marker(top: Top) -> float:
	return trigger_rpm / max(top.initial_rpm, 1.0)
