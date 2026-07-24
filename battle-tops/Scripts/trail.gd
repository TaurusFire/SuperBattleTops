class_name TopTrail
extends MeshInstance3D

## A ribbon trailing behind a top, hugging the arena floor. Points are sampled
## by distance rather than per frame, so the trail looks the same regardless of
## frame rate, and each point remembers how fast the top was moving when it was
## laid down — so the ribbon swells where the top was quick and narrows where
## it dawdled.

@export var top: Top
@export var trail_colour := Color(1.0, 0.3, 0.25)

@export_group('Shape')
## Seconds before a point has fully faded away.
@export var duration := 0.9
## Ribbon width at `speed_reference`. Faster than that is capped.
@export var max_width := 0.007
## Speed that earns full width.
@export var speed_reference := 0.6
## Below this speed no new points are laid, so a near-stationary top doesn't
## pile points on top of each other.
@export var min_speed := 0.03
## How far the top must travel before another point is recorded.
@export var sample_distance := 0.004
## Lift above the floor, to avoid z-fighting with the arena mesh.
@export var height_offset := 0.0015
@export var max_points := 64

var _points: Array[Dictionary] = []      # {pos: Vector3, age: float, width: float}
var _imm: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	if top == null:
		top = get_parent() as Top

	# Draw in raw world space: the ribbon's vertices are world positions, so the
	# node must contribute no transform of its own.
	top_level = true

	_imm = ImmediateMesh.new()
	mesh = _imm

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Depth test stays on so the wall occludes the trail, but writing depth
	# would make overlapping ribbon segments cull each other.
	_mat.no_depth_test = false
	_mat.disable_receive_shadows = true
	material_override = _mat


func _process(delta: float) -> void:
	# Forced every frame — top_level alone doesn't clear a transform set in the
	# editor, and any residual offset would displace the whole ribbon.
	global_transform = Transform3D.IDENTITY

	_age_points(delta)
	if _should_record():
		_record_point()
	_rebuild()


func _age_points(delta: float) -> void:
	var i := 0
	while i < _points.size():
		_points[i]["age"] += delta
		if _points[i]["age"] >= duration:
			_points.remove_at(i)
		else:
			i += 1


func _should_record() -> bool:
	if top == null:
		return false
	if top.current_state not in [Top.State.ACTIVE, Top.State.DYING]:
		return false
	if top._velocity.length() < min_speed:
		return false
	if _points.is_empty():
		return true
	var last: Vector3 = _points[-1]["pos"]
	return last.distance_to(_current_pos()) >= sample_distance


func _current_pos() -> Vector3:
	return Vector3(top.global_position.x,
				   top.global_position.y + height_offset,
				   top.global_position.z)


func _record_point() -> void:
	var speed := top._velocity.length()
	_points.append({
		"pos": _current_pos(),
		"age": 0.0,
		"width": max_width * clamp(speed / speed_reference, 0.15, 1.0),
	})
	if _points.size() > max_points:
		_points.pop_front()


func _rebuild() -> void:
	_imm.clear_surfaces()
	if _points.size() < 2:
		return

	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size():
		var p: Dictionary = _points[i]
		var pos: Vector3 = p["pos"]

		# Direction of travel at this point, from its neighbours.
		var dir: Vector3
		if i == 0:
			dir = _points[1]["pos"] - pos
		elif i == _points.size() - 1:
			dir = pos - _points[i - 1]["pos"]
		else:
			dir = _points[i + 1]["pos"] - _points[i - 1]["pos"]
		dir.y = 0.0
		if dir.length() < 0.0001:
			continue
		dir = dir.normalized()

		# Perpendicular in the horizontal plane, so the ribbon lies flat.
		var side := dir.cross(Vector3.UP).normalized()

		# Fade with age, and taper the oldest end to a point.
		var life: float = 1.0 - (p["age"] / duration)
		var w: float = p["width"] * life
		var col := trail_colour
		col.a = trail_colour.a * life * life     # squared, so it fades off fast

		_imm.surface_set_color(col)
		_imm.surface_add_vertex(pos - side * w)
		_imm.surface_set_color(col)
		_imm.surface_add_vertex(pos + side * w)

	_imm.surface_end()
