class_name Ability
extends Resource

## Base class for a fighter's ability. Abilities hook into the top's existing
## systems rather than replacing them: most will only implement one or two of
## these. A top with no ability should carry a stat budget bonus to compensate.

## Called every frame while the top is ACTIVE, before the intent machine runs.
func tick(_top: Top, _delta: float) -> void:
	pass

## True while the ability owns the top's movement. The intent machine skips
## its own transitions when this returns true, so the ability's chosen intent
## isn't overwritten by collisions or timers.
func controls_movement(_top: Top) -> bool:
	return false

## The RPM the combat formulas should use. Normally the top's current spin,
## but an ability can substitute something else — Kamikaze returns the initial
## RPM so a spent top still strikes at full power.
func attack_rpm(top: Top) -> float:
	return top.current_rpm

## Chance to prevent the ordinary death when RPM runs out. Return true to keep
## the top alive; the ability is then responsible for ending it.
func intercept_death(_top: Top) -> bool:
	return false

func strike_multiplier(_top: Top) -> float:
	return 1.0
	
func vertical_bias(_top: Top) -> float:
	return 1.0
	
func gauge_marker(_top: Top) -> float:
	return -1.0
	
## Multiplier applied to the top's movement speed. Lets a passive ability
## modify how the top moves without taking control of where it goes.
func speed_multiplier(_top: Top) -> float:
	return 1.0

## Called after this top has been involved in a collision, whether it dealt
## the hit or received it.
func on_collision(_top: Top) -> void:
	pass
