class_name StatEntry
extends Resource

## One row on the stat card: which value to read, and how much of it earns
## another half star.

## Label shown beside the stars.
@export var label := "POWER"
## Property name on TopStats to read.
@export var stat_property := "base_knockback"
## How much of the raw value earns another half star.
@export var per_half_star := 10.0
## Ceiling, so an outlier can't overflow the row.
@export var max_stars := 5
## Set for values where lower is better — decay rates, for instance.
@export var invert := false
## Only used when `invert` is true: the value subtracted from before rating.
@export var invert_baseline := 100.0
