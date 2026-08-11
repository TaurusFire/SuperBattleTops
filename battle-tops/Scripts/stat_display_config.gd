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

static func survival_time(stats: TopStats, dead_rpm: float) -> float:
	var b := stats.rpm_base_decay_rate
	var k := stats.rpm_decay_frac
	var r0 := stats.initial_rpm

	if k <= 0.0001:
		# Purely linear decay; the log form degenerates.
		return (r0 - dead_rpm) / max(b, 0.0001)
	return (1.0 / k) * log((b + k * r0) / (b + k * dead_rpm))
