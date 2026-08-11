class_name Top
extends Node3D

## A spinning top. Movement is scripted rather than physically simulated: the
## top steers itself according to an `intent` that responds to its opponent,
## and combat outcomes come from a stat-driven formula rather than momentum
## transfer. Physics is used only for the ground raycast.
##
## Per-fighter values live on a `TopStats` resource and are copied across in
## `_apply_stats`. Values that define how the *system* behaves — the combat
## maths, the intent timings, the wobble curve — stay as exports here, so
## changing them doesn't mean editing every fighter.

# ══════════════════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════════════════

enum State { INTRO, COUNTDOWN, ACTIVE, DYING, KNOCKED_OUT, STOPPED }

## What a top is trying to do right now. CLOSING persists until a collision
## interrupts it; the others run on `_intent_timer`.
enum Intent { CLOSING, ORBITING, RECOVERING, IDLE, DODGING, COUNTERING, FLEEING, ABILITY, COMBO }

signal stopped(top: Top)
signal entered_dying(top: Top)
signal dodged(top: Top)
signal ability_triggered(top: Top, ability: Ability)
signal combo_hit(top: Top, target: Top, index: int)

var current_state: State = State.INTRO
var intent: Intent = Intent.CLOSING


# ══════════════════════════════════════════════════════════════════════════
#  IDENTITY
# ══════════════════════════════════════════════════════════════════════════

## The fighter's identity: name, appearance, and every value that differs
## between tops. Assign a different .tres per instance to build a roster.
@export var stats: TopStats

@onready var spin_visual: MeshInstance3D = $OrientationPivot/TopMesh
@onready var orientation_pivot: Node3D = $OrientationPivot
var manager: GameManager

## Derived from the mesh AABB in _ready, so it tracks whatever the resource
## supplied rather than needing to be kept in sync by hand.
var radius: float


# ══════════════════════════════════════════════════════════════════════════
#  PER-TOP VALUES — all set from `stats` in _apply_stats
# ══════════════════════════════════════════════════════════════════════════

# RPM
var initial_rpm = 4500.0
var rpm_base_decay_rate = 20.0
var rpm_decay_frac = 0.015

# Combat
var base_knockback: float
var base_damage: float
var defence: float
var weight: float

# Engagement
var move_speed = 0.55
var aggression = 0.5
var orbit_radius = 0.07
var dodge_skill = 0.3
var base_responsiveness = 2.0

# Idle — only used once there's no opponent left to engage.
var idle_radius = 0.08
var idle_speed = 0.35

var ability: Ability

# ══════════════════════════════════════════════════════════════════════════
#  SHARED TUNING — exports that shape the system, not individual fighters
# ══════════════════════════════════════════════════════════════════════════

@export_group('Combat')
## Reference RPM the power curves are measured against.
@export var ref_rpm = 2500.0
## Fraction of knockback converted to an upward hop.
@export var vertical_fraction = 0.25
## How much the RPM advantage swings knockback. At 0 it's ignored; the
## multiplier is centred on 1.0 so changing this never shifts the baseline.
@export var dominance_influence = 0.3
## What a stationary or retreating hit is worth relative to a full charge.
@export var min_momentum_mult = 0.2
## Random scatter on knockback direction, in radians, scaled down by momentum
## so heavy hits stay decisive and glancing ones vary.
@export var knockback_scatter = 1.1
## Floor on damage as a fraction of the raw hit, so defence can never fully
## negate an attack and no matchup becomes unwinnable.
@export_range(0.0, 1.0) var min_damage_frac = 0.7
## Closing speed that earns full momentum credit.
@export var velo_reference = 0.2
## Vertical knockback multiplier at full RPM — a top spinning fast is settled
## on its foot and resists being launched.
@export var vertical_mult_high_rpm = 0.4
## Multiplier as RPM approaches zero, when the top is barely gripping.
@export var vertical_mult_low_rpm = 1.45
## Shape of the transition. Below 1 the rise starts early and eases in; above
## 1 it stays low through most of the match then climbs sharply near death.
@export var vertical_mult_curve = 1.25


@export_group('RPM')
## The threshold at which a top is beaten.
@export var dead_rpm = 5.0

@export_group('Spinning')
## Visible spin is capped well below real RPM to avoid wagon-wheel aliasing;
## the render frame rate can't sample fast rotation faithfully.
@export var max_visual_spin :float = 50.0
## Scales visible spin without touching RPM. Used by the intro to present a
## top clearly at the apex.
var spin_display_scale := 1.0

@export_group('Engagement')
## Orbit duration at aggression 0 and 1 respectively.
@export var orbit_time_max = 1.8
@export var orbit_time_min = 1.1
## Recovery duration at aggression 0 and 1, scaled by how hard the hit was.
@export var recover_time_max = 2.0
@export var recover_time_min = 1.2
## Knockback that earns a full-length recovery.
@export var recover_reference = 0.6
## Below this fraction of reference, a hit only triggers a brief orbit.
@export var recover_threshold = 0.6
@export var max_speed := 2.5


@export_subgroup('Fleeing')
## RPM ratio below which a top stops seeking contact and tries to survive.
## Unlike RECOVERING this isn't a timed reaction to a hit — it persists for as
## long as the top is this badly hurt.
@export_range(0.0, 1.0) var flee_threshold = 0.10
## Hysteresis: the top only stops fleeing once it climbs back above
## `flee_threshold + flee_hysteresis`. Without it a top hovering right on the
## line flickers between fleeing and closing every frame.
@export var flee_hysteresis = 0.05
## Distance it tries to keep from the nearest opponent.
@export var flee_distance = 0.10
## Speed multiplier while fleeing. Above 1 so a desperate top can actually
## escape rather than being run down immediately.
@export var flee_speed = 1.5
## How strongly it favours circling over running directly away. Pure retreat
## backs into the wall; some tangential motion keeps it mobile.
@export_range(0.0, 1.0) var flee_tangent = 0.1


## How much the approach arcs rather than charging straight in.
@export_range(0.0, 1.5) var approach_curve = 0.3



## Minimum gap to hold, as a multiple of combined radii. Applies regardless of
## intent so tops can never settle inside each other.
@export var separation_factor = 1.05
@export var separation_strength = 2.0

## Constant inward pull standing in for the bowl's curvature, as a multiple of
## move_speed at the rim. Applies everywhere, so keep it modest — a large value
## flattens the usable arena rather than just discouraging the edge.
@export var slope_strength = 0.5

## Radius, as a fraction of the arena, beyond which a top counts as loitering.
@export_range(0.0, 1.0) var loiter_radius_frac = 0.45

## Seconds at the edge before the inward pull reaches full strength.
@export var loiter_patience = 0.5

## Peak inward pull.
@export var loiter_pull = 2

## How fast the timer unwinds once back inside. Higher forgets sooner.
@export var loiter_recovery = 4


@export_group('Dodging')
## Distance at which an incoming charge can be read and slipped.
@export var dodge_trigger_range = 0.07
## Cosine threshold on how head-on the approach must be. Lower catches arcing
## approaches; higher demands a dead-straight charge.
@export var dodge_alignment = 0.6
## Seconds of lateral burst.
@export var dodge_duration = 0.15
## Speed multiplier during the slip.
@export var dodge_speed = 1.2
## Seconds before another dodge is possible, so it stays a moment.
@export var dodge_cooldown_time = 1
## Seconds of counter-attack after a successful slip.
@export var counter_duration = 0.45
## Speed multiplier while countering.
@export var counter_speed = 2.5
## How far the slip angles backward along the opponent's approach rather than
## purely sideways. 0 is a pure sidestep; higher ends up behind the charge.
@export_range(0.0, 1.5) var dodge_back_bias := 0.25
@export var counter_abandon_range = 0.15

@export_group('Wall')
## Steering suspension after a wall bounce, so it reads as a ping not a guide.
@export var wall_recoil_time = 0.1
## Steering suspension after a top-on-top hit, so a pair can't lock together.
@export var contact_recoil_time = 0.12
@export var wall_bounce_scatter := 0.4
## Inward steering near the rim, so intents pointing outward don't pin a top
## against the wall.
@export var wall_avoid_strength = 3.0
@export var wall_avoid_range = 0.03
@export var wall_damage_cooldown := 0.3
var _wall_damage_timer := 0.0
var _wall_contact := false

@export_group('Spawning')
@export var drop_duration = 0.6
@export var drop_height := 0.1

@export_group('Wobble')
@export var max_wobble_angle = 0.4
## RPM ratio below which wobble begins.
@export var wobble_onset = 0.15
@export var precession_rate = 6.28

@export_group('Topple')
@export var topple_duration = 1.2
@export var topple_target = 1.4

@export_group('Orientation')
@export var max_curve_lean = 0.15

@export_group('Knockout')
@export var ko_drag = 0.4
@export var ko_kill_depth = 0.5

@export_group('Combo')
## Closing speed needed for a hit to be combo-eligible. Below this the top
## isn't committed enough to follow up.
@export var combo_speed_threshold := 0.04
## Chance of a follow-up after the first hit, before aggression scales it.
@export_range(0.0, 1.0) var combo_base_chance := 0.9
## How much aggression moves that chance. At 0.5, an aggression-1.0 fighter
## gets 1.5x the base chance and an aggression-0 fighter 0.5x.
@export_range(0.0, 1.0) var combo_aggression_weight := 0.9
## Each successive hit multiplies the chance by this, so long combos are rare
## without needing a hard cap.
@export_range(0.1, 1.0) var combo_chance_decay := 0.99
## Seconds between hits in a combo.
@export var combo_interval := 0.12
## Power of each follow-up relative to the first. 1.0 keeps every hit at full
## strength; lower makes a combo taper.
@export_range(0.2, 1.0) var combo_falloff := 0.9
## Hard ceiling, as a safety net rather than a design constraint.
@export_range(0.0, 1.0) var combo_knockback_scale := 0.05
@export var combo_finisher_scale = 2.0
@export var combo_max_hits := 6
## Seconds the target is held after each combo hit, so the flurry stays in
## contact. Suppressing knockback isn't enough on its own — the target simply
## steers away under its own power.
@export var combo_stun_time := 1
## Speed multiplier while pressing a combo. Modest — the target is stunned, so
## this only needs to close the small gap each hit opens.
@export var combo_press_speed = 3
## Movement retained while stunned. A little reads better than a total freeze.
@export_range(0.0, 1.0) var combo_stun_mobility = 0.00
## How much knockback the attacker absorbs while pressing a combo. Its intent
## keeps it aimed at the target, but without this the recoil physically throws
## it back and the flurry becomes a chase.
@export_range(0.0, 1.0) var combo_self_knockback = 0.15
@export var combo_pursuit_range = 0.10
@export var combo_stun_margin = 1.5
var _combo_target: Top
var _combo_timer := 0.0
var _combo_index := 0      
var _combo_chance := 0.0
var _combo_velo_bonus := 0.0
var _stun_timer := 0.0

# ══════════════════════════════════════════════════════════════════════════
#  RUNTIME STATE
# ══════════════════════════════════════════════════════════════════════════

const ARENA_LAYER = 1 << 2
var _counter_target: Top

# Arena facts, pushed in by the manager via _set_arena. The top never reaches
# upward to find them.
var arena_centre: Vector2
var arena_radius: float
var wall_radius: float
var wall_bounce: float
var wall_damage: float
var knockout_radius: float
var gravity: float

var opponents: Array[Top] = []

# Motion
var _velocity = Vector2.ZERO
var _vertical_velocity = 0.0
var _airborne = false
var _wall_recoil_timer = 0.0

# Spin
var current_rpm: float
var _visual_rpm = 0.0          # scripted separately during the countdown
var _spin_frozen = false

# Containment
var _loiter_time = 0.0

# Intent
var _intent_timer = 0.0
var _orbit_dir = 1.0
var _dodge_dir_vec = Vector2.ZERO
var _dodge_cooldown = 0.0

# Which way round the idle ring this top travels.
var _idle_dir = 1.0 if randf() < 0.5 else -1.0

# Orientation
var _wobble_phase = 0.0
var _topple_elapsed = 0.0
var _topple_start_lean = 0.0

# Countdown
var _countdown_remaining = 3.0
var _countdown_elapsed = 0.0
var countdown_duration = 3.0

# Read by the manager and the VFX after each collision.
var last_damage_dealt = 0.0
var last_knockback_dealt = 0.0

var rpm_ratio: float:
	get: return current_rpm / max(initial_rpm, 1.0)

# ══════════════════════════════════════════════════════════════════════════
#  SETUP
# ══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	assert(stats != null, "%s has no TopStats assigned." % name)
	_apply_stats()

	# Radius comes from the mesh, so this must follow _apply_stats — otherwise
	# it would measure whatever placeholder the scene shipped with.
	var aabb = spin_visual.mesh.get_aabb()
	radius = max(aabb.size.x, aabb.size.z) * 0.5
	current_rpm = initial_rpm


## Copies the resource onto the top. Done once at startup rather than reading
## through `stats` at every use site, so the per-frame paths stay direct field
## access and the resource stays a pure description.
func _apply_stats() -> void:

	if stats.mesh != null:
		spin_visual.mesh = stats.mesh
		for i in stats.materials.size():
			spin_visual.set_surface_override_material(i, stats.materials[i])

	initial_rpm = stats.initial_rpm
	rpm_base_decay_rate = stats.rpm_base_decay_rate
	rpm_decay_frac = stats.rpm_decay_frac

	base_knockback = stats.base_knockback
	base_damage = stats.base_damage
	defence = stats.defence
	weight = stats.weight

	move_speed = stats.move_speed
	aggression = stats.aggression
	orbit_radius = stats.orbit_radius
	dodge_skill = stats.dodge_skill
	base_responsiveness = stats.base_responsiveness

	idle_radius = stats.idle_radius
	idle_speed = stats.idle_speed

	ability = stats.ability

## Arena facts are told to the top rather than looked up, so it never depends
## on where it sits in the scene tree.
func _set_arena(
	centre: Vector2,
	arena_r: float,
	arena_wall_radius: float,
	arena_wall_bounce: float,
	arena_wall_damage: float,
	arena_gravity: float,
	arena_knockout_radius: float
) -> void:
	arena_centre = centre
	arena_radius = arena_r
	wall_radius = arena_wall_radius
	wall_bounce = arena_wall_bounce
	wall_damage = arena_wall_damage
	gravity = arena_gravity
	knockout_radius = arena_knockout_radius


## Name for display — the roster name, not the node name.
func display_name() -> String:
	return stats.display_name if stats != null else name


# ══════════════════════════════════════════════════════════════════════════
#  MAIN LOOP
# ══════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	_update_visual_spin(delta)
	_update_orientation(delta)

	# Gravity is match-level, not ACTIVE-only — otherwise a top dying mid-hop
	# would freeze in the air. KNOCKED_OUT handles its own fall.
	if current_state in [State.ACTIVE, State.DYING]:
		_update_vertical(delta)

	match current_state:
		State.INTRO: pass
		State.COUNTDOWN: _update_countdown(delta)
		State.ACTIVE: _update_active(delta)
		State.KNOCKED_OUT: _update_knocked_out(delta)



func _update_active(delta: float) -> void:
	var decay = rpm_base_decay_rate + current_rpm * rpm_decay_frac
	current_rpm = max(current_rpm - decay * delta, 0.0)

	if ability != null:
		ability.tick(self, delta)

	# An ability may keep the top alive past its normal death — Kamikaze uses
	# that window to spend itself rather than simply winding down.
	if current_rpm < dead_rpm and not (ability != null and ability.intercept_death(self)):
		_enter_dying()
		return

	_update_loiter(delta)
	_update_intent(delta)
	_update_combo(delta)
	
	_wall_recoil_timer = max(_wall_recoil_timer - delta, 0.0)
	_wall_damage_timer = max(_wall_damage_timer - delta, 0.0)
	_stun_timer = max(_stun_timer - delta, 0.0)

	if not _airborne and _wall_recoil_timer <= 0.0:
		var desired = _desired_velocity()
		if _stun_timer > 0.0:
			print("%s stunned: timer=%.4f mobility=%s desired before=%.3f after=%.3f" % [
				display_name(), _stun_timer, combo_stun_mobility,
				desired.length(), (desired * combo_stun_mobility).length()])
			desired = desired * combo_stun_mobility + _separation() * move_speed
		var responsiveness = base_responsiveness * pow(rpm_ratio, 0.4)
		if intent == Intent.COUNTERING:
			responsiveness = 10
		elif intent == Intent.COMBO:
			responsiveness = 15
		elif intent == Intent.ABILITY and ability is KamikazeAbility:
			responsiveness = (ability as KamikazeAbility).agility
		_velocity = _velocity.lerp(desired, clamp(responsiveness * delta, 0.0, 1.0))
	else:
		
		# Separation still applies during recoil, or a pair knocked into each
		# other has nothing to break them apart.
		_wall_recoil_timer = max(_wall_recoil_timer - delta, 0.0)
		if intent != Intent.COMBO:
			_velocity += _separation() * move_speed * delta * 4.0

	_apply_velocity(delta)
	_apply_wall_collision()

	if _airborne and _horizontal_pos().distance_to(arena_centre) > knockout_radius:
		_enter_knocked_out()


func _apply_velocity(delta: float) -> void:
	if _velocity.length() > max_speed:
		_velocity = _velocity.normalized() * max_speed
	
	var pos = global_position
	pos.x += _velocity.x * delta
	pos.z += _velocity.y * delta
	global_position = pos


func _horizontal_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


# ══════════════════════════════════════════════════════════════════════════
#  MOVEMENT — intent drives direction, move_speed drives magnitude
# ══════════════════════════════════════════════════════════════════════════

## Everything the top wants to do this frame, summed: the intent's direction,
## plus two corrections that always apply regardless of intent.
func _desired_velocity() -> Vector2:
	var speed = move_speed * pow(rpm_ratio, 0.3)
	if ability != null:
		speed *= ability.speed_multiplier(self)
	var iv := _intent_velocity(speed)
	var wa = _wall_avoidance()
	var sep = _separation() * speed
	var slope = _slope_force() * speed
	var pull = _centre_pull()
		
	var d = _horizontal_pos().distance_to(arena_centre)
	
	if intent == Intent.COMBO:
		var overlap = _separation()
		if _horizontal_pos().distance_to(_combo_target._horizontal_pos())\
			 < (radius + _combo_target.radius) * 0.6:
			return _clamp_to_arena(iv + _wall_avoidance() + overlap * speed)
	
	return _clamp_to_arena(iv + wa + sep + slope + pull)


func _intent_velocity(speed: float) -> Vector2:
	var target = _nearest_opponent()
	if target == null:
		return _idle_velocity(speed)

	var to_them = target._horizontal_pos() - _horizontal_pos()
	var dist = to_them.length()
	if dist < 0.0001:
		return _velocity
	var toward = to_them / dist

	match intent:
		Intent.CLOSING:
			# Arc in rather than charging straight, so tops meet off-axis and
			# glance rather than colliding dead-centre every time. The lateral
			# component fades with distance, so the top commits at the end.
			var tangent = Vector2(-toward.y, toward.x) * _orbit_dir
			var curve_amount = approach_curve * (1.0 - aggression * 0.5)
			var curve = curve_amount * clamp(dist / max(orbit_radius, 0.001), 0.0, 1.0)
			return (toward + tangent * curve).normalized() * speed
		
		Intent.COMBO:
			var ct = _combo_target if _combo_target != null else target
			var to_ct = ct._horizontal_pos() - _horizontal_pos()
			if to_ct.length() < 0.0001:
				return _velocity
			return to_ct.normalized() * speed * combo_press_speed
		
		Intent.ORBITING:
			# Circle at orbit_radius: tangential motion plus a radial nudge
			# proportional to how far off that distance we currently are.
			var tangent = Vector2(-toward.y, toward.x) * _orbit_dir
			var radial_error = (dist - orbit_radius) / max(orbit_radius, 0.001)
			var radial = toward * clamp(radial_error, -1.0, 1.0)
			return (tangent + radial * 0.6).normalized() * speed

		Intent.DODGING:
			# Pure lateral burst — the opponent's momentum carries them past.
			return _dodge_dir_vec * move_speed * dodge_speed

		Intent.COUNTERING:
			# A committed punish: aimed at whoever we slipped, and immune to
			# the RPM speed falloff, so a failing top can still retaliate.
			var ct = _counter_target if _counter_target != null else target
			var to_ct = ct._horizontal_pos() - _horizontal_pos()
			if to_ct.length() < 0.0001:
				return _velocity
			return to_ct.normalized() * move_speed * counter_speed
		
		Intent.ABILITY:
			return _ability_velocity(speed, target)
		
		Intent.FLEEING:
			# Keep away without simply running: a blend of retreat and orbit,
			# so the top stays mobile and doesn't reverse into the wall. The
			# radial part reverses sign once it's further out than
			# `flee_distance`, so it holds a ring rather than fleeing forever.
			var away = -toward
			var flee_tan = Vector2(-toward.y, toward.x) * _orbit_dir
			var gap_error = clamp((flee_distance - dist) / max(flee_distance, 0.001), -1.0, 1.0)
			var radial_flee = away * gap_error
			var inward_bias = (arena_centre - _horizontal_pos()).normalized() * 0.35
			return (radial_flee * (1.0 - flee_tangent)
				+ flee_tan * flee_tangent
				+ inward_bias).normalized() * speed * flee_speed

		Intent.RECOVERING:
			if dist < (radius + target.radius) * 1.2 and _velocity.length() > 0.001:
				return _velocity.normalized() * speed * 0.8
			# Retreat inward rather than straight away, so a top doesn't back
			# itself into the rim.
			var from_centre := _horizontal_pos() - arena_centre
			var inward_weight = clamp(from_centre.length() / (arena_radius * 0.3), 0.0, 1.0)
			var inward := Vector2.ZERO
			if from_centre.length() > 0.001:
				inward = -from_centre.normalized() * inward_weight
			return (-toward * 0.5 + inward * 0.8).normalized() * speed * 0.8

	return _idle_velocity(speed)


## Fallback when there's nobody left to fight: circle the arena centre at a
## fixed radius. Deliberately plain — by the time this runs the match is
## already decided, so it only needs to look purposeful, not interesting.
func _idle_velocity(_speed: float) -> Vector2:
	var from_centre = _horizontal_pos() - arena_centre
	var dist = from_centre.length()
	if dist < 0.001:
		return Vector2.RIGHT * idle_speed
 
	var outward = from_centre / dist
	var tangent = Vector2(-outward.y, outward.x) * _idle_dir
 
	# Converge on the ring while travelling around it: the radial term is
	# proportional to how far off `idle_radius` we currently are.
	var radial_error = clamp((dist - idle_radius) / max(idle_radius, 0.001), -1.0, 1.0)
	var radial = -outward * radial_error
 
	return (tangent + radial * 0.7).normalized() * idle_speed * pow(rpm_ratio, 0.3)


## Inward push that grows as the top nears the containment limit. Without it,
## intents pointing outward drive a top into the rim and hold it there.
func _wall_avoidance() -> Vector2:
	var from_centre = _horizontal_pos() - arena_centre
	var dist = from_centre.length()
	var limit = wall_radius - radius
	var margin = limit - dist
	if margin > wall_avoid_range or dist < 0.0001:
		return Vector2.ZERO
	var closeness = 1.0 - clamp(margin / wall_avoid_range, 0.0, 1.0)
	return -from_centre.normalized() * closeness * wall_avoid_strength


## Push away from any opponent we're overlapping. Unlike the intents, this
## always applies — a top should never be able to rest inside another.
func _separation() -> Vector2:
	var push = Vector2.ZERO
	for o in opponents:
		if o.current_state != State.ACTIVE:
			continue
		var gap = _horizontal_pos() - o._horizontal_pos()
		var dist = gap.length()
		var min_gap = (radius + o.radius) * separation_factor
		if dist >= min_gap or dist < 0.0001:
			continue
		var overlap = 1.0 - (dist / min_gap)
		push += gap.normalized() * overlap * separation_strength
	return push


func _nearest_opponent() -> Top:
	var best: Top = null
	var best_dist = INF
	for o in opponents:
		if o.current_state != State.ACTIVE:
			continue
		var d = _horizontal_pos().distance_squared_to(o._horizontal_pos())
		if d < best_dist:
			best_dist = d
			best = o
	return best

## Constant inward pull from the bowl's slope. The floor is parabolic
## (y = K·r²), so its gradient — and therefore the inward component of gravity
## acting along it — grows linearly with distance from centre.
##
## This complements rather than replaces the other two containment forces:
## the slope biases everything gently toward the middle, wall avoidance is a
## hard stop in the last few centimetres, and the loiter pull catches the case
## neither handles — a top whose intent holds it out at the edge, where a
## constant force reaches equilibrium and stops correcting.
func _slope_force() -> Vector2:
	var from_centre = _horizontal_pos() - arena_centre
	var dist = from_centre.length()
	if dist < 0.0001:
		return Vector2.ZERO
	return -from_centre.normalized() * (dist / arena_radius) * slope_strength


## Tracks how long the top has spent out near the rim. Unlike wall avoidance,
## which only fires within a fixed margin of the limit, this catches a top
## orbiting persistently at the edge without ever touching it.
func _update_loiter(delta: float) -> void:
	var dist_frac = _horizontal_pos().distance_to(arena_centre) / arena_radius
	if dist_frac > loiter_radius_frac:
		_loiter_time = min(_loiter_time + delta, loiter_patience)
	else:
		_loiter_time = max(_loiter_time - delta * loiter_recovery, 0.0)


## Inward pull that builds the longer a top loiters at the edge, and relaxes
## once it comes back in. Squared so it stays gentle at first and only becomes
## insistent after a sustained stay.
func _centre_pull() -> Vector2:
	if _loiter_time <= 0.0:
		return Vector2.ZERO
	var t = _loiter_time / loiter_patience
	var inward = arena_centre - _horizontal_pos()
	var dist = inward.length()
	if inward.length() < 0.0001:
		return Vector2.ZERO
	var closeness = clamp(dist / 0.03, 0.0, 1.0)
	return inward.normalized() * 0.7 * loiter_pull * t * t * closeness


func _clamp_to_arena(desired: Vector2) -> Vector2:
	var from_centre := _horizontal_pos() - arena_centre
	var dist := from_centre.length()
	var limit := wall_radius - radius
	if dist < limit - 0.002 or dist < 0.0001:
		return desired
	var normal := from_centre / dist
	var outward := desired.dot(normal)
	if outward <= 0.0:
		return desired
	return desired - normal * outward

## Movement while an ability has control. Only Kamikaze exists so far; when
## there are more, this dispatches on the ability type.
func _ability_velocity(_speed: float, fallback: Top) -> Vector2:
	var k := ability as KamikazeAbility
	if k == null:
		return Vector2.ZERO

	if k.phase_of(self) == KamikazeAbility.Phase.TELEGRAPH:
		return Vector2.ZERO         # holding still while it flashes
	if k.phase_of(self) == KamikazeAbility.Phase.SPENDING:
		return Vector2.ZERO
	
	var t: Top = k.target_of(self)
	if t == null:
		t = fallback
	if t == null:
		return Vector2.ZERO

	var to_t := t._horizontal_pos() - _horizontal_pos()
	if to_t.length() < 0.0001:
		return _velocity
	# Ignores the RPM speed falloff — this is everything the top has left.
	return to_t.normalized() * move_speed * k.charge_speed

# ══════════════════════════════════════════════════════════════════════════
#  INTENT MACHINE
# ══════════════════════════════════════════════════════════════════════════

func _update_intent(delta: float) -> void:
	_intent_timer = max(_intent_timer - delta, 0.0)
	_dodge_cooldown = max(_dodge_cooldown - delta, 0.0)
	
	if ability != null and ability.controls_movement(self):
		intent = Intent.ABILITY
		return
	
	if _combo_index > 0:
		intent = Intent.COMBO
		return
	
	var target = _nearest_opponent()
	if target == null:
		intent = Intent.IDLE
		return

	# A slip runs to completion, then flows into the counter.
	if intent == Intent.DODGING:
		if _intent_timer <= 0.0:
			_begin_countering()
		return

	# Only try to read a charge when we aren't already committed to something.
	if _stun_timer <= 0.0 and target._stun_timer <= 0.0 \
		and intent in [Intent.CLOSING, Intent.ORBITING] \
			and randf() < dodge_skill * delta * 6.0:
		var slip = _incoming_charge(target)
		if slip != Vector2.ZERO:
			_begin_dodging(slip, target)
			return
	
	if intent == Intent.COUNTERING:
		# Null-check before dereferencing: the target can die mid-counter.
		var lost = _counter_target == null \
			or _counter_target.current_state != State.ACTIVE
		if not lost:
			# Distance is only judged after a grace period. The dodge's whole
			# job was to create separation, so measuring straight away would
			# abandon every counter before it had a chance to turn around.
			var elapsed = counter_duration - _intent_timer
			lost = elapsed > 0.2 \
				and _horizontal_pos().distance_to(_counter_target._horizontal_pos()) > counter_abandon_range

		if lost or _intent_timer <= 0.0:

			_counter_target = null
			_velocity *= 0.15
			_begin_orbiting()
		return
	
	# Fleeing overrides the ordinary cycle: a top this badly hurt shouldn't be
	# seeking contact at all. Checked after the dodge and counter branches so
	# it can't interrupt a slip already in progress — a dying top that reads a
	# charge should still be allowed to punish it.
	if _should_flee():
		if intent != Intent.FLEEING:
			_begin_fleeing()
		return
	elif intent == Intent.FLEEING:
		# Recovered enough to fight again.
		_begin_closing()
		return

	# An expired orbit or recovery returns to the hunt. CLOSING has no timer —
	# it persists until a collision interrupts it.
	if intent == Intent.IDLE or (intent != Intent.CLOSING and _intent_timer <= 0.0):
		_begin_closing()


## Hysteresis band, so a top sitting near the threshold doesn't flicker
## between fleeing and fighting on alternate frames.
func _should_flee() -> bool:
	var target := _nearest_opponent()
	if target == null:
		return false

	var band = flee_threshold
	if intent == Intent.FLEEING:
		band += flee_hysteresis      # hysteresis, so it doesn't flicker
	if rpm_ratio >= band:
		return false
	# Only run from someone who can still finish you.
	return target.current_rpm > current_rpm * 2


func _begin_fleeing() -> void:
	intent = Intent.FLEEING
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	# No timer: this persists for as long as the RPM condition holds.
	_intent_timer = 0.0


func _begin_closing() -> void:
	intent = Intent.CLOSING
	_intent_timer = 0.0
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0


func _begin_orbiting() -> void:
	intent = Intent.ORBITING
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_intent_timer = lerpf(orbit_time_max, orbit_time_min, aggression)


func _begin_recovering(severity: float) -> void:
	intent = Intent.RECOVERING
	_intent_timer = lerpf(recover_time_max, recover_time_min, aggression) * severity


func _begin_dodging(slip: Vector2, from: Top) -> void:
	intent = Intent.DODGING
	_dodge_dir_vec = slip
	_counter_target = from
	_intent_timer = dodge_duration
	_dodge_cooldown = dodge_cooldown_time
	_velocity = slip * move_speed * dodge_speed
	dodged.emit(self)


func _begin_countering() -> void:
	intent = Intent.COUNTERING
	_intent_timer = counter_duration
	_velocity *= 0.15

## A charge is readable when the opponent is close, moving fast, and heading
## roughly straight at us. Returns the direction to slip — perpendicular to
## their approach, on whichever side has more room.
func _incoming_charge(target: Top) -> Vector2:
	if _dodge_cooldown > 0.0 or dodge_skill <= 0.0:
		return Vector2.ZERO

	var to_us := _horizontal_pos() - target._horizontal_pos()
	var dist := to_us.length()
	if dist > dodge_trigger_range or dist < 0.0001:
		return Vector2.ZERO

	if target._velocity.length() < 0.05:
		return Vector2.ZERO
	if target._velocity.normalized().dot(to_us / dist) < dodge_alignment:
		return Vector2.ZERO

	# Slip perpendicular to their line of travel, on the inward side so the
	# dodge doesn't pin us against the wall.
	var perp := Vector2(-to_us.y, to_us.x).normalized()
	if perp.dot(_horizontal_pos() - arena_centre) > 0.0:
		perp = -perp

	# Bias backward along their approach, so we end up behind the charge
	# rather than beside it — a much better angle to counter from.
	var back := -target._velocity.normalized()
	return (perp + back * dodge_back_bias).normalized()


# ══════════════════════════════════════════════════════════════════════════
#  COMBAT
# ══════════════════════════════════════════════════════════════════════════

func attack(opponent: Top, velo_bonus: float) -> void:
	if current_state != State.ACTIVE or opponent.current_state != State.ACTIVE:
		last_knockback_dealt = 0.0
		last_damage_dealt = 0.0
		return
	
	var attack_rpm := current_rpm
	var strike := 1.0
	if ability != null:
		attack_rpm = ability.attack_rpm(self)
		strike = ability.strike_multiplier(self)
	strike *= pow(combo_falloff, float(_combo_index))
	
	# Momentum: a charging top lands a full hit, a stationary or retreating one
	# only glances. This is what makes aggression pay.
	var momentum = clamp(velo_bonus / velo_reference, 0.0, 1.3)
	var momentum_mult = lerpf(min_momentum_mult, 1.0, momentum)

	# --- Damage -----------------------------------------------------------
	# Front-loaded: the exponent gives a high-RPM top a real early advantage
	# without collapsing damage to nothing at the tail.
	var power = pow((attack_rpm + ref_rpm) / ref_rpm, 1)
	var adj_damage = base_damage * power * momentum_mult * strike
	
	# Defence subtracts, but never below a fraction of the raw hit — so a
	# strong attacker always chips a tanky defender.
	var dmg_dealt = max(
		adj_damage - opponent.defence,
		adj_damage * min_damage_frac
	)
	
	last_damage_dealt = dmg_dealt
	opponent._receive_dmg(dmg_dealt)
	#print(
		#"\nAttacker: ", self.display_name(),
		#"\nVelocity: ", self._velocity.length(),
		#"\nMomentum: ", momentum,
		#"\nMomentum Mult: ", momentum_mult,
		#"\nAdjusted Damage: ", adj_damage,
		#"\nDamage Dealt: ", dmg_dealt,
		#"\nReceiver: ", opponent.display_name()
	#)
	
	# --- Knockback --------------------------------------------------------
	# Its own, flatter power curve: knockback is the spectacle, and shouldn't
	# collapse late the way damage does.
	var kb_power = (attack_rpm + ref_rpm) / ref_rpm
	var total_rpm = attack_rpm + opponent.current_rpm
	var dominance = attack_rpm / total_rpm if total_rpm > 0.0 else 0.5
	var dominance_mult = 1.0 + (dominance - 0.5) * 2.0 * dominance_influence

	var weight_factor = weight / (weight + opponent.weight)
	
	var continuing = _roll_combo(opponent, velo_bonus)
	var base_term = base_knockback * pow(kb_power, 0.5) * weight_factor * 0.75
	var applied = base_term * dominance_mult * momentum_mult * strike
	if _combo_index > 0 and continuing:
		# Mid-flurry: keep the pair in contact.
		applied *= combo_knockback_scale
	elif _combo_index > 0:
		# The finisher — the suppressed knockback of the whole combo, delivered
		# at once.
		applied *= combo_finisher_scale
	
	#print(
		#"\nAttacker: ", self.display_name(),
		#"\nVelocity: ", self._velocity.length(),
		#"\nKB Power: ", kb_power,
		#"\nMomentum: ", momentum,
		#"\nMomentum Mult: ", momentum_mult,
		#"\nDominance Mult: ", dominance_mult,
		#"\nAdj KB 1: ", base_term,
		#"\nAdj KB 2: ", applied,
		#"\nReceiver: ", opponent.display_name()
	#)
	# --- Direction --------------------------------------------------------
	# Scatter keeps clashes from all resolving along the same line. Scaled down
	# by momentum so heavy hits drive through and glancing ones vary.
	var scatter = knockback_scatter * (1.0 - momentum * 0.6)
	var dir = opponent._horizontal_pos() - _horizontal_pos()
	dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	dir = dir.rotated(randf_range(-scatter, scatter))

	var vert_bias := 1.0
	if ability != null:
		vert_bias = ability.vertical_bias(self)
	
	last_knockback_dealt = applied
	_maybe_continue_combo(opponent, velo_bonus)
	opponent._receive_kb(applied, dir, vert_bias)
	
	if not continuing:
		if _combo_index > 0:
			# Released on the finisher: the launch should send a top that can
			# react, not a limp one.
			opponent._stun_timer = 0.0
		_end_combo()
	
	if ability is KamikazeAbility:
		(ability as KamikazeAbility).on_hit_landed(self)
		



## Applies damage that has already had defence accounted for.
func _receive_dmg(dmg: float) -> void:
	current_rpm = max(current_rpm - dmg, 0.0)


func _receive_kb(knockback: float, dir: Vector2, vertical_bias := 1.0) -> void:
	
	if ability != null:
		ability.on_collision(self)
	# Parenthesised deliberately: without them this divides by 20 and then
	# multiplies by the weight ratio, so heavier tops take more knockback.
	knockback = knockback / (20.0 * (weight / 0.18))
	if _combo_index > 0:
		knockback *= combo_self_knockback
		print("%s combo self-kb suppressed to %.4f" % [display_name(), knockback])
		
	_velocity += dir * knockback / vertical_bias

	# Lower RPM means a top less settled on its foot, so it pops higher.
	var stability = pow(clamp(rpm_ratio, 0.0, 1.0), vertical_mult_curve)
	var vert_mult = lerpf(vertical_mult_low_rpm, vertical_mult_high_rpm, stability)
	_vertical_velocity += knockback * vertical_fraction * vert_mult * vertical_bias

	# A hard hit knocks a top onto the back foot; a light one just breaks the
	# charge. This is what produces the clash-separate-clash rhythm.
	var severity = clamp(knockback / recover_reference, 0.0, 1.0)
	# A fleeing top stays fleeing — being hit is exactly why it's running, and
	# dropping to ORBITING would send it back toward its attacker.
	if intent == Intent.COMBO or (ability != null and ability.controls_movement(self)):
		pass
	elif not _should_flee():
		if severity > recover_threshold:
			_begin_recovering(severity)
		else:
			_begin_orbiting()
	
	if _combo_index <= 0:
		_wall_recoil_timer = max(_wall_recoil_timer, contact_recoil_time)



func _apply_wall_collision() -> void:
	if _airborne:
		return

	var from_centre = _horizontal_pos() - arena_centre
	var normal = from_centre.normalized()
	var dist = from_centre.length()
	var limit = wall_radius - radius

	if dist < limit:
		_wall_contact = false
		return
	var before = _horizontal_pos()
	print("%s wall snap: %.4f -> %.4f" % [display_name(), before.distance_to(arena_centre), _horizontal_pos().distance_to(arena_centre)])
	
	var outward_speed := _velocity.dot(normal)
	var bounce = 0.0 if (_combo_index > 0 or _stun_timer > 0.0) else wall_bounce
	if outward_speed > 0.05:
		var tangential = _velocity - normal * outward_speed
		var rebound = -normal * outward_speed * bounce
		_velocity = tangential + rebound

		# Cooldown rather than a contact flag: a top bouncing off and back
		# re-arms the flag each time, so gating on fresh contact alone lets
		# repeated glancing impacts drain it dry.
		if _wall_damage_timer <= 0.0:
			_receive_dmg(wall_damage)
			print(display_name(), ' took wall damage')
			_wall_damage_timer = wall_damage_cooldown
			
	elif outward_speed > 0.0:
		_velocity -= normal * outward_speed

	# Sustained contact must not hold steering off — only the initial impact.
	if _wall_contact:
		_wall_recoil_timer = 0.0
	_wall_contact = true

	# Snap just inside the limit so the early return catches us next frame,
	# rather than re-triggering and chipping damage while pressed against it.
	var inset = limit - 0.001
	global_position.x = arena_centre.x + normal.x * inset
	global_position.z = arena_centre.y + normal.y * inset

## Rolls for a follow-up hit. The chance decays with each successive hit, so a
## long combo is the compound product of several rolls — rare without a cap
## having to enforce it.
func _maybe_continue_combo(opponent: Top, velo_bonus: float) -> void:
	if _combo_index >= combo_max_hits:
		_end_combo()
		return
	if opponent.current_state != State.ACTIVE:
		_end_combo()
		return

	# Only a committed approach earns a follow-up. A top that was drifting or
	# retreating when it connected has nothing to press with.
	if _combo_index == 0:
		if velo_bonus < combo_speed_threshold:
			print("%s: no combo, velo %.3f below %.3f" % [
				display_name(), velo_bonus, combo_speed_threshold])
			return
		var aggression_scale = 1.0 + (aggression - 0.5) * 2.0 * combo_aggression_weight
		_combo_chance = combo_base_chance * aggression_scale
		_combo_velo_bonus = velo_bonus
		print("%s: combo eligible, chance %.2f" % [display_name(), _combo_chance])

	if randf() >= _combo_chance:
		_end_combo()
		return

	_combo_index += 1
	_combo_chance *= combo_chance_decay
	_combo_target = opponent
	_combo_timer = combo_interval
	opponent._apply_stun(combo_stun_time)
	print("%s combo QUEUED hit %d, distance now %.4f, interval %.3f, my vel %.3f, their vel %.3f" % [
		display_name(), _combo_index,
		_horizontal_pos().distance_to(opponent._horizontal_pos()),
		combo_interval, _velocity.length(), opponent._velocity.length()])

func _roll_combo(opponent: Top, velo_bonus: float) -> bool:
	if _combo_index >= combo_max_hits:
		return false
	if opponent.current_state != State.ACTIVE:
		return false

	if _combo_index == 0:
		if velo_bonus < combo_speed_threshold:
			return false
		var aggression_scale = 1.0 + (aggression - 0.5) * 2.0 * combo_aggression_weight
		_combo_chance = min(combo_base_chance * aggression_scale, 1.0)
		_combo_velo_bonus = velo_bonus

	if randf() >= _combo_chance:
		return false

	_combo_index += 1
	_combo_chance *= combo_chance_decay
	_combo_target = opponent
	_combo_timer = combo_interval
	opponent._apply_stun(combo_interval * combo_stun_margin)
	return true

## Delivers a queued follow-up. The hits land without the tops separating, so
## the viewer reads one contact with several impacts rather than a sequence of
## approaches — which is what makes a flurry legible at this scale.
func _update_combo(delta: float) -> void:
	if _combo_index <= 0:
		return
	if _combo_timer > 0.0:
		_combo_timer -= delta
		return

	if _combo_target == null or _combo_target.current_state != State.ACTIVE:
		_end_combo()
		return
	# Lost them: a combo is a flurry at contact, not a pursuit.
	var d := _horizontal_pos().distance_to(_combo_target._horizontal_pos())
	if d > (radius + _combo_target.radius) * 1.15:
		print("%s combo broken: distance %.4f, at r=%.4f, vel=%.3f, target vel=%.3f, intent=%d, target intent=%d, stun=%.3f" % [
			display_name(), d, _horizontal_pos().distance_to(arena_centre),
			_velocity.length(), _combo_target._velocity.length(),
			intent, _combo_target.intent, _combo_target._stun_timer])
		if d < combo_pursuit_range:
			_combo_timer = combo_interval * 0.5
			return
		_end_combo()
		return

	combo_hit.emit(self, _combo_target, _combo_index)
	print("%s combo hit %d on %s (chance now %.2f, falloff %.2f)" % [
		display_name(), _combo_index, _combo_target.display_name(),
		_combo_chance, pow(combo_falloff, float(_combo_index))])
	var struck = _combo_target
	var depth = _combo_index
	attack(struck, _combo_velo_bonus)
	if manager != null:
		manager.report_combo_hit(self, struck, depth)

func _end_combo() -> void:
	if _combo_index > 0:
		if _combo_target != null:
			_combo_target._stun_timer = 0.0
		_begin_orbiting()
	_combo_index = 0
	_combo_target = null
	_combo_timer = 0.0

func _apply_stun(duration: float) -> void:
	_stun_timer = max(_stun_timer, duration)
	_velocity *= 0.2
# ══════════════════════════════════════════════════════════════════════════
#  VERTICAL
# ══════════════════════════════════════════════════════════════════════════

func _update_vertical(delta: float) -> void:
	var surface_y = _surface_y_at(global_position.x, global_position.z)
	_vertical_velocity -= gravity * delta
	var new_y = global_position.y + _vertical_velocity * delta
	if new_y <= surface_y:
		new_y = surface_y
		_vertical_velocity = 0.0
		_airborne = false
	else:
		_airborne = true
	global_position.y = new_y


func _surface_y_at(x: float, z: float) -> float:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		Vector3(x, 1.0, z), Vector3(x, -1.0, z))
	query.collision_mask = ARENA_LAYER
	var hit = space.intersect_ray(query)
	if hit:
		return hit.position.y
	return 0.0


# ══════════════════════════════════════════════════════════════════════════
#  SPIN AND ORIENTATION
# ══════════════════════════════════════════════════════════════════════════

func _update_visual_spin(delta: float) -> void:
	if _spin_frozen:
		return
	var ratio = clamp(current_rpm / max(initial_rpm, 1.0), 0.0, 1.0)
	spin_visual.rotate_y(-max_visual_spin * pow(ratio, 0.3) * spin_display_scale * delta)

func _update_orientation(delta: float) -> void:
	match current_state:
		State.ACTIVE:
			# Both the amount and the precession rate scale with wobble, so
			# instability builds gently rather than switching on.
			_wobble_phase += precession_rate * delta * _wobble_amount()
			_apply_wobble(max_wobble_angle * _wobble_amount())
		State.DYING:
			_update_topple(delta)
		State.STOPPED:
			pass
		State.KNOCKED_OUT:
			pass
		State.INTRO:
			pass

## Ramps from 0 at `wobble_onset` to 1 at zero RPM. The fourth power keeps it
## near nothing for most of the descent then rises sharply near death.
func _wobble_amount() -> float:
	if rpm_ratio >= wobble_onset:
		return 0.0
	return pow((wobble_onset - rpm_ratio) / wobble_onset, 4.0)


## Outward tilt from sitting on a curved bowl, growing toward the rim.
func _curvature_lean() -> Vector3:
	var radial = _horizontal_pos() - arena_centre
	if radial.length() < 0.001:
		return Vector3.ZERO
	var dist_frac = clamp(radial.length() / arena_radius, 0.0, 1.0)
	var outward = Vector3(radial.x, 0.0, radial.y).normalized()
	return outward * sin(max_curve_lean * dist_frac)


## Composes the up-axis from vertical, bowl curvature and precession, then
## applies it to the pivot. The mesh spins inside this, so tilt and spin never
## fight over the same transform.
func _apply_wobble(wobble: float) -> void:
	var up = Vector3.UP
	up += _curvature_lean()
	up += Vector3(sin(_wobble_phase), 0.0, cos(_wobble_phase)) * sin(wobble)
	orientation_pivot.basis = _basis_from_up(up.normalized())


func _basis_from_up(up: Vector3) -> Basis:
	var b = Basis()
	b.y = up
	var ref = Vector3.RIGHT if abs(up.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD
	b.z = ref.cross(up).normalized()
	b.x = up.cross(b.z).normalized()
	return b.orthonormalized()




# ══════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════

func set_countdown_remaining(t: float) -> void:
	_countdown_remaining = t


func _update_countdown(delta: float) -> void:

	var surface_y = _surface_y_at(global_position.x, global_position.z)
	if _countdown_remaining > drop_duration:
		global_position.y = surface_y + drop_height
	else:
		var t = 1.0 - (_countdown_remaining / drop_duration)
		global_position.y = surface_y + drop_height * (1.0 - ease(t, 2.5))


func begin_countdown() -> void:
	current_state = State.COUNTDOWN
	orientation_pivot.basis = Basis()

func begin_match() -> void:
	current_rpm = initial_rpm
	current_state = State.ACTIVE
	# Stagger the opening so the first clash isn't identical every match.
	if randf() > aggression:
		_begin_orbiting()
	else:
		_begin_closing()


func _enter_dying() -> void:
	current_state = State.DYING
	_topple_elapsed = 0.0
	# Pick up from whatever lean the wobble had reached, so the fall is
	# continuous rather than snapping upright first.
	_topple_start_lean = max_wobble_angle * _wobble_amount()
	entered_dying.emit(self)


func _update_topple(delta: float) -> void:
	_topple_elapsed += delta
	current_rpm = max(current_rpm - rpm_base_decay_rate * delta, 0.0)
	_wobble_phase += precession_rate * delta

	# Carry the killing blow's knockback through the fall, bleeding off as it
	# goes. Without this a top dies exactly where it was hit and only the
	# vertical component reads, which looks like it was launched straight up.
	_velocity = _velocity.lerp(Vector2.ZERO, clamp(2.5 * delta, 0.0, 1.0))
	_apply_velocity(delta)
	_apply_wall_collision()

	var t = clamp(_topple_elapsed / topple_duration, 0.0, 1.0)
	_apply_wobble(lerp(_topple_start_lean, topple_target, ease(t, 2.0)))

	if t >= 1.0:
		_enter_stopped()


func _enter_knocked_out() -> void:
	current_state = State.KNOCKED_OUT
	current_rpm = 0.0
	entered_dying.emit(self)


func _update_knocked_out(delta: float) -> void:
	# Free fall with no surface snap, so it drops past the arena floor.
	_vertical_velocity -= gravity * delta
	global_position.y += _vertical_velocity * delta

	_velocity = _velocity.lerp(Vector2.ZERO, clamp(ko_drag * delta, 0.0, 1.0))
	_apply_velocity(delta)

	_wobble_phase += precession_rate * delta * 2.0
	_apply_wobble(max_wobble_angle * 1.5)

	if global_position.y < arena_centre.y - ko_kill_depth:
		_enter_stopped()


func _enter_stopped() -> void:
	current_state = State.STOPPED
	stopped.emit(self)


## Halts movement, decay and visible spin, leaving the top standing where it
## is. Used at the end of a match so the winner doesn't keep winding down.
func freeze_in_place() -> void:
	if current_state == State.STOPPED:
		return
	current_state = State.STOPPED
	_velocity = Vector2.ZERO
	_vertical_velocity = 0.0
	_spin_frozen = true
