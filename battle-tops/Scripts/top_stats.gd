class_name TopStats
extends Resource

## Everything that makes a top *that* top: identity, appearance, and the
## simulation values that differ between fighters.
##
## Values shared across all tops — reference_weight, dominance_influence,
## ref_rpm, wobble and topple timings — deliberately stay as exports on the
## Top itself. Those define how the combat maths behaves rather than what any
## individual fighter is like, and putting them here would mean changing the
## formula required editing every resource.

@export_group("Identity")
## Shown on the intro card, the gauge, and the result banner.
@export var display_name := "UNNAMED"
## Free-text archetype label — "ATTACK", "DEFENCE", "STAMINA". Purely for
## display; nothing in the simulation branches on it.
@export var archetype := ""

@export_group("Appearance")
@export var mesh: Mesh
## Surface overrides, in surface order. For the generated tops that's
## [Rim, Body] — or whichever order the OBJ's usemtl groups came out in.
@export var materials: Array[Material] = []
## Used for the trail and anywhere else the fighter needs a signature colour.
@export var trail_colour := Color(1.0, 0.3, 0.25)
@export var name_colour := Color(1.0, 1.0, 1.0)
@export var name_colour_secondary := Color(1.0, 1.0, 1.0, 0.0)

@export_group("RPM")
@export var initial_rpm := 4500.0
## Flat loss per second.
@export var rpm_base_decay_rate := 20.0
## Proportional loss per second, so high-RPM tops bleed faster early on.
@export var rpm_decay_frac := 0.015

@export_group("Combat")
@export var base_knockback := 16.0
@export var base_damage := 50.0
@export var defence := 30.0
@export var weight := 0.1

@export_group("Engagement")
## Peak linear speed in metres per second at full RPM. The arena is 0.38
## across, so 0.55 crosses it in about seven tenths of a second.
@export var move_speed := 0.55
## How readily this fighter seeks contact. Higher means shorter orbits, quicker
## recoveries, and more direct approaches — attack high, defence low.
@export var aggression := 0.5
## Preferred distance from the opponent while circling.
@export var orbit_radius := 0.07
@export var dodge_skill := 0.3
@export var base_responsiveness := 5.0

@export_group("Idle")
## Only used once there's nobody left to fight — the ring this top circles
## while the match winds down.
@export var idle_radius := 0.08
@export var idle_speed := 0.35


@export_group("Ability")
## Optional. A top without one should carry a stat budget bonus.
@export var ability: Ability
