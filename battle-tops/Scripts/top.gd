class_name Top
extends RigidBody3D

enum State { COUNTDOWN, ACTIVE, DYING, KNOCKED_OUT, STOPPED}
var current_state: State = State.COUNTDOWN

signal stopped(top: Top)
signal entered_dying(top: Top)

var radius: float

@export_group('Wall')
@export var wall_recoil_time := 0.15
var wall_bounce : float
var wall_damage : float
var _wall_recoil_timer := 0.0


@export_group('RPM')
@export var initial_rpm := 4500.0
@export var rpm_base_decay_rate := 20.0
@export var rpm_decay_frac := 0.015
var dead_rpm := 5

# spinning
@export_group('Spinning')
@onready var spin_visual: MeshInstance3D = $OrientationPivot/TopMesh
var _visual_rpm := 0.0 # for spawning
@export var max_visual_spin := 40.0


@export_group('Patterns')
# pattern seeking
@export_subgroup('Pattern Picking')
@export var pattern_pool: Array[MovementPattern] = []
@export var pattern_weights: Array[float] = []

@export_subgroup('Pattern Seeking')
@export var movement_pattern: MovementPattern
@export var speed_margin := 1.4 # affects move_cap, affects the max move per frame
@export var base_responsiveness := 1 # affects how much actual move gets to max move
@export var rotation_rate := 0.1

# affects pattern scaling
@export_subgroup('Pattern Scaling')
@export_range(0.0, 1.0) var max_rpm_scale := 0.8 # full rpm orbit as frac of arena radius
@export_range(0.0, 1.0) var scale_floor := 0.4 # min frac of baseline

# countdown and spawning
@export_group('Spawning')
@export var drop_duration := 0.6
@export var drop_height := 0.1
var _countdown_remaining := 3.0
var _countdown_elapsed := 0.0
var countdown_duration := 3.0

# wobble
@export_group('Wobble')
@export var max_wobble_angle := 0.5
@export var wobble_onset := 0.4
@export var precession_rate := 3.14
var _wobble_phase := 0.0

#
@export_group('Topple')
@export var topple_duration := 1.2
@export var topple_target := 1.4
var _topple_elapsed := 0.0
var _topple_start_lean := 0.0

# orientation
@export_group('Orientation')
@onready var orientation_pivot: Node3D = $OrientationPivot
@export var max_curve_lean := 0.1

@export_group('Vertical')
var gravity : float
var _vertical_velocity := 0.0
var _airborne := false

@export_group('Combat')
@export var base_knockback := 16
@export var defence := 30.0
@export var base_damage := 50
@export var weight := 0.1
@export var ref_rpm := 4000.0
var vertical_fraction := 0.2

@export_group('Centre Drift')
@export var drift_wander := 0.05
@export var drift_pull := 1.5
@export var drift_max := 0.04
@export var drift_damping := 0.7
var _centre_offset := Vector2.ZERO
var _centre_velocity := Vector2.ZERO

# raycasting
const ARENA_LAYER := 1 << 2

var arena_centre: Vector2
var arena_radius: float
var wall_radius: float

var _pattern_time := 0.0
var current_rpm : float
var _velocity: Vector2 = Vector2.ZERO
var _angle = 0
var _rotation_phase = 0

# attacking
var opponents: Array[Top] = []

var rpm_ratio: float:
	get:
		return current_rpm/initial_rpm

var root_rpm_ratio: float:
	get:
		return pow(rpm_ratio, 0.5)


func _ready() -> void:
	var aabb = spin_visual.mesh.get_aabb()
	radius = max(aabb.size.x, aabb.size.z) * 0.5
	_begin_kinematic()
	current_rpm = initial_rpm


func _physics_process(delta: float) -> void:
	_update_visual_spin(delta)
	_update_orientation(delta)

	
	if current_state in [State.ACTIVE, State.DYING, State.KNOCKED_OUT]:
		_update_vertical(delta)
	match current_state:
		State.COUNTDOWN: _update_countdown(delta)
		State.ACTIVE: _update_active(delta)


func _apply_velocity(delta: float) -> void:
	var pos := global_position
	pos.x += _velocity.x * delta
	pos.z += _velocity.y * delta
	global_position = pos


func _horizontal_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


#func _find_mesh() -> Node3D:
	#for child in get_children():
		#if child is MeshInstance3D:
			#return child
	#return null

func attack(opponent: Top, velo_bonus: float) -> void:
	if current_state != State.ACTIVE or opponent.current_state != State.ACTIVE:
		return
	
	var power := pow(((current_rpm + ref_rpm) / ref_rpm), 1)
	
	# Damage
	var adj_damage = (base_damage + 100 * velo_bonus) * power
	var dmg_dealt = max(base_damage, adj_damage)
	opponent._receive_dmg(dmg_dealt)
	
	# knockback
	var total_rpm = current_rpm + opponent.current_rpm
	var dominance = current_rpm / total_rpm if total_rpm > 0 else 0.5
	var defence_term = opponent.defence * 0.5
	var raw = (base_knockback + 10 * velo_bonus) * pow(power, 0.5) / defence_term
	var weight_factor := weight / (weight + opponent.weight) 
	var applied = max(raw, 0.0) * weight_factor * (dominance*1.3)

	# direction
	var dir := Vector2(opponent.global_position.x, opponent.global_position.z) \
				- Vector2(global_position.x, global_position.z)
	dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	
	print(
		self.name,
		' damage_dealt:',
		dmg_dealt,
		' knockback_dealt:',
		applied
	)
	
	opponent._receive_kb(applied, dir)
	
	
func _receive_dmg(dmg: float) -> void:
	current_rpm = max(current_rpm - dmg, 0.0)

func _receive_kb(knockback: float, dir: Vector2) -> void:
	_velocity += dir * knockback
	_vertical_velocity += knockback * vertical_fraction
	movement_pattern = _pick_weighted_pattern()
	

func _get_target(angle: float, pattern_scale: float, rot_phase: float) -> Vector2:
	var target = movement_pattern.get_target(angle, pattern_scale, rot_phase)
	return target


func _set_arena(
	centre: Vector2,
	radius:float,
	arena_wall_radius: float,
	arena_wall_bounce: float,
	arena_wall_damage: float,
	arena_gravity: float
	) -> void:
	arena_centre = centre
	arena_radius = radius
	wall_radius = arena_wall_radius
	wall_bounce = arena_wall_bounce
	wall_damage = arena_wall_damage
	gravity = arena_gravity


func _begin_kinematic() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true


#func _end_kinematic() -> void:
	#_velocity = Vector2.ZERO
	#freeze = false
	##linear_velocity = Vector3.ZERO


func _surface_y_at(x:float, z:float) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x,1.0,z)
	var to := Vector3(x,-1.0,z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ARENA_LAYER
	var hit := space.intersect_ray(query)
	if hit:
		return hit.position.y
	return 0


func _get_pattern_scale() -> float:
	var rpm_factor = scale_floor + (1-scale_floor) * pow(rpm_ratio, 0.3)
	var radius = arena_radius * max_rpm_scale * rpm_factor
	return min(radius, arena_radius)


func begin_match() -> void:
	current_rpm = initial_rpm
	current_state = State.ACTIVE


func _update_visual_spin(delta) -> void:
	var rpm_for_spin = _visual_rpm if current_state == State.COUNTDOWN else current_rpm
	#var rad_per_sec : float = rpm_for_spin * TAU / 60
	var rad_per_sec : float = max_visual_spin * pow((rpm_for_spin / initial_rpm), 0.35)
	spin_visual.rotate_y(-rad_per_sec * delta)


func set_countdown_remaining(t: float) -> void:
	_countdown_remaining = t


func _update_countdown(delta: float) -> void:
	_countdown_elapsed += delta
	
	var surface_y = _surface_y_at(global_position.x, global_position.z)
	if _countdown_remaining > drop_duration:
		global_position.y = surface_y + drop_height
	else:
		var t = 1.0 - (_countdown_remaining / drop_duration)
		var eased = ease(t, 2.5)
		global_position.y = surface_y + drop_height * (1.0 - eased)
	
	var progress : float = clamp(_countdown_elapsed/countdown_duration, 0, 1)
	var eased = pow(progress, 3.5)
	_visual_rpm = initial_rpm * eased

func _update_active(delta) -> void:
	_pattern_time += delta
	_angle += movement_pattern.angular_speed * pow(rpm_ratio, 0.2) * delta
	_rotation_phase += rotation_rate * delta
	
	if Input.is_action_just_pressed('ui_accept'):
		_vertical_velocity = 0.5
	
	var decay = rpm_base_decay_rate + current_rpm * rpm_decay_frac
	current_rpm = max(current_rpm - decay * delta, 0.0)
	if current_rpm < dead_rpm:
		print(self.name, ' entering dying')
		_enter_dying()
		print(self.name, ' dead')
	
	_update_centre_drift(delta)
	
 
	
	if not _airborne and _wall_recoil_timer <= 0.0:
		
		var centre := arena_centre + _centre_offset
		var pattern_scale = _get_pattern_scale()
		var local := _get_target(_angle, pattern_scale, _rotation_phase)
		var target := centre + local  
		
		var target_speed = movement_pattern.angular_speed * root_rpm_ratio * pattern_scale
		var move_cap = target_speed * speed_margin
		
		var distance_delta = target - _horizontal_pos()

		var max_move = distance_delta.normalized() * move_cap
		var responsiveness = base_responsiveness * pow(rpm_ratio, 0.3)
		_velocity = _velocity.lerp(max_move, clamp(responsiveness * delta, 0, 1))
	else:
		_wall_recoil_timer = max(_wall_recoil_timer - delta, 0.0)
	
	_apply_velocity(delta)
	_apply_wall_collision()

func _wobble_amount() -> float:
	if rpm_ratio >= wobble_onset:
		return 0.0
	var t = (wobble_onset-rpm_ratio)/wobble_onset
	return pow(t, 4.0)


func _curvature_lean() -> Vector3:
	var radial := _horizontal_pos() - arena_centre
	var dist_frac = clamp(radial.length() / arena_radius, 0.0, 1.0)
	if radial.length() < 0.001:
		return Vector3.ZERO
	var lean_angle = max_curve_lean * dist_frac
	var outward = Vector3(radial.x, 0, radial.y).normalized()
	return outward * sin(lean_angle)


func _update_orientation(delta: float) -> void:
	match current_state:
		State.ACTIVE:
			_wobble_phase += precession_rate * delta * _wobble_amount()
			var wobble = max_wobble_angle * _wobble_amount()
			_apply_wobble(wobble)
		State.DYING:
			_update_topple(delta)
		State.STOPPED:
			pass


func _apply_wobble(wobble: float) -> void:

	var up := Vector3.UP
	up += _curvature_lean()
	up += Vector3(sin(_wobble_phase), 0, cos(_wobble_phase)) * sin(wobble)
	up = up.normalized()
	
	orientation_pivot.basis = _basis_from_up(up)


func _basis_from_up(up: Vector3) -> Basis:
	var b = Basis()
	b.y = up
	var ref := Vector3.RIGHT if abs(up.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD
	b.z = ref.cross(up).normalized()
	b.x = up.cross(b.z).normalized()
	return b.orthonormalized()


func _enter_dying() -> void:
	current_state = State.DYING
	_topple_elapsed = 0.0
	_topple_start_lean = max_wobble_angle * _wobble_amount()
	entered_dying.emit(self)


func _update_topple(delta: float) -> void:
	_topple_elapsed += delta
	current_rpm = max(current_rpm - rpm_base_decay_rate * delta, 0.0)
	_wobble_phase += precession_rate * delta 
	
	var t = clamp(_topple_elapsed / topple_duration, 0.0, 1.0)
	var eased := ease(t, 2.0)
	var lean = lerp(_topple_start_lean, topple_target, eased)
	_apply_wobble(lean)
	
	if t >= 1.0:
		print(self.name, " entering stopped")
		_enter_stopped()


func _update_vertical(delta: float) -> void:
	var surface_y = _surface_y_at(global_position.x, global_position.y)
	_vertical_velocity -= gravity * delta
	var new_y := global_position.y + _vertical_velocity * delta
	if new_y <= surface_y:
		new_y = surface_y
		_vertical_velocity = 0.0
		_airborne = false
	else:
		_airborne = true
	global_position.y = new_y


func _enter_stopped() -> void:
	current_state = State.STOPPED
	print(self.name, ' stopped')
	stopped.emit(self)

func _pick_weighted_pattern() -> MovementPattern:
	var total := 0.0
	for w in pattern_weights:
		total += w
	var roll := randf() * total
	var acc := 0.0
	for i in pattern_pool.size():
		acc += pattern_weights[i]
		if roll <= acc:
			return pattern_pool[i]
	return pattern_pool.back()

func _update_centre_drift(delta: float) -> void:
	var nudge := Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0) * drift_wander
	_centre_velocity += nudge
	
	_centre_velocity -= _centre_offset * drift_pull * delta
	_centre_velocity *= drift_damping
	_centre_offset += _centre_velocity * delta
	
	if _centre_offset.length() > drift_max:
		_centre_offset = _centre_offset.normalized() * drift_max
		
func _apply_wall_collision() -> void:
	if _airborne:
		return 

	var from_centre := _horizontal_pos() - arena_centre
	var dist := from_centre.length()
	var limit := wall_radius - radius
	if dist < limit:
		return

	var normal := from_centre.normalized()
	var outward_speed := _velocity.dot(normal)
	if outward_speed > 0.0:
		_velocity -= normal * outward_speed * (1.0 + wall_bounce)
		_wall_recoil_timer = wall_recoil_time
		#print(name, " WALL HIT — speed in: ", outward_speed, " bounce vel: ", _velocity)
		_receive_dmg(wall_damage - defence)
	
	global_position.x = arena_centre.x + normal.x * (limit)
	global_position.z = arena_centre.y + normal.y * (limit)
