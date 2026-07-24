class_name ClashSparks
extends Node3D

## Emits a burst of sparks at the contact point of a collision, scaled by how
## hard the hit was. One node handles every clash in the match; it repositions
## itself to each contact point before firing.

@export var manager: GameManager

@export_group('Scale')

@export var knockback_reference := 0.3
@export var damage_reference := 40
@export var rpm_reference := 3000
## Particles at full strength. Weak hits emit proportionally fewer.
@export var max_particles := 48
## Below this fraction of reference, no sparks at all.
@export var threshold := 0.4

@export_group('Look')
@export var spark_colour := Color(1.0, 0.906, 0.724, 1.0)
@export var spark_size := 0.003
@export var min_speed := 0.60
@export var max_speed := 1.2
@export var lifetime := 0.08
## Upward bias, so sparks arc rather than spraying flat.
@export var upward_bias := 0.3

var _particles: GPUParticles3D

func _ready() -> void:
	_particles = GPUParticles3D.new()
	add_child(_particles)
	_particles.emitting = false
	_particles.one_shot = true
	_particles.explosiveness = 1.0        # whole burst at once, not a stream
	_particles.amount = max_particles
	_particles.lifetime = lifetime
	_particles.local_coords = false       # sparks stay put once emitted
	_particles.draw_pass_1 = _make_mesh()
	_particles.process_material = _make_process_material()
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _make_spark_texture()
	mat.albedo_color = spark_colour
	mat.disable_receive_shadows = true
	_particles.material_override = mat
	
	manager.collision_occurred.connect(_on_collision)


func _make_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.004

	# Spray outward in all directions, biased upward.
	m.direction = Vector3(0, upward_bias, 0)
	m.spread = 70.0
	m.initial_velocity_min = min_speed
	m.initial_velocity_max = max_speed

	m.gravity = Vector3(0, -1, 0)
	m.damping_min = 5
	m.damping_max = 10

	m.scale_min = 0.5
	m.scale_max = 1.0
	# Shrink over life, so sparks die out rather than vanishing abruptly.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	m.scale_curve = tex

	m.color = spark_colour
	return m

func _make_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(spark_size, spark_size)   # square, not a streak
	return quad

func _make_spark_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))       # opaque centre
	g.set_color(1, Color(1, 1, 1, 0))       # transparent edge
	# Ease the falloff so the core stays bright and only the rim fades.
	g.add_point(0.45, Color(1, 1, 1, 0.85))

	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

func _on_collision(a: Top, b: Top) -> void:
	
	var knockback_ref: float = max(a.last_knockback_dealt, b.last_knockback_dealt) / knockback_reference
	var damage_ref: float = max(a.last_damage_dealt, b.last_damage_dealt) / damage_reference
	var rpm_ref: float = max(a.current_rpm, b.current_rpm) / rpm_reference
	
	var raw: float = (knockback_ref + damage_ref + rpm_ref) / 3
	var strength: float = clamp(sqrt(raw), 0.15, 1.0)
	print('raw: ', raw, ' strength: ', strength)
	
	if strength < threshold:
		return
	
	var a_pos := Vector3(a.global_position.x, 0.0, a.global_position.z)
	var b_pos := Vector3(b.global_position.x, 0.0, b.global_position.z)
	var to_b := b_pos - a_pos
	var dir := to_b.normalized() if to_b.length() > 0.0001 else Vector3.FORWARD

	var contact := a_pos + dir * a.radius
	contact.y = min(max(a.global_position.y, b.global_position.y) + a.radius * 0.4, 0.05)
	global_position = contact

	_particles.amount_ratio = clamp(strength, 0.15, 1.0)
	_particles.restart()
	print("spark fired at ", global_position,
		  " ratio=", _particles.amount_ratio,
		  " emitting=", _particles.emitting,
		  " visible=", visible)
