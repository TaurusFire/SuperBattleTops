class_name StatDisplayConfig
extends Resource

## Maps raw simulation values to star ratings for display. Kept as a resource
## so the thresholds live in one place rather than being scattered through the
## UI — change the balance and the cards follow.

## One entry per bar shown on the card.
@export var entries: Array[StatEntry] = []


## Star rating for a fighter's value on one stat, in half-star units.
static func rate(value: float, per_half_star: float, max_stars: int) -> float:
	if per_half_star <= 0.0:
		return 0.0
	var halves = floor(value / per_half_star)
	return min(halves * 0.5, float(max_stars))
