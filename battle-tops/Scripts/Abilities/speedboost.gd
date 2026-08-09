class_name SpeedboostAbility
extends Ability

## Every clash makes the top faster. Builds toward a ceiling and decays when
## the top goes a while without contact, so it rewards staying in the fight
## rather than simply surviving to the end of a long match.

## Speed added per collision, as a fraction of the top's base move speed.
@export var gain_per_hit := 0.25
## Ceiling on the accumulated bonus, as a fraction of base move speed.
@export var max_bonus := 4
## How much of the bonus bleeds away per second without contact.
@export var decay_per_second := 0.5
## Seconds after a clash before the bonus starts decaying.
@export var grace := 1.0

# Per-top state: the resource is shared between every fighter using it, so it
# cannot hold this in plain fields.
var _bonus := {}
var _since_hit := {}


## Read by the gauge or any VFX that wants to show how charged the top is.
func bonus_of(top: Top) -> float:
	return _bonus.get(top, 0.0)


func charge_fraction(top: Top) -> float:
	return bonus_of(top) / max(max_bonus, 0.001)


func tick(top: Top, delta: float) -> void:
	var idle: float = _since_hit.get(top, 0.0) + delta
	_since_hit[top] = idle
	if idle > grace:
		_bonus[top] = max(bonus_of(top) - decay_per_second * delta, 0.0)


func on_collision(top: Top) -> void:
	_bonus[top] = min(bonus_of(top) + gain_per_hit, max_bonus)
	_since_hit[top] = 0.0


func speed_multiplier(top: Top) -> float:
	return 1.0 + bonus_of(top)
