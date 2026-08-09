class_name TopDebugViz
extends MeshInstance3D

@export var target_colour := Color.ORANGE
@export var centre_colour := Color.CYAN
@export var velocity_colour := Color.RED
@export var marker_size := 0.03
@export var velocity_arrow_scale := 0.30
@export var trail_length := 600        # frames of history (~10s at 60fps)
@export var trail_colour := Color.GREEN
@export var target_trail_colour := Color.ORANGE

var _trail: Array[Vector3] = []
var _target_trail: Array[Vector3] = []

var _top: Top
var _imm: ImmediateMesh
var _mat: StandardMaterial3D

func _ready() -> void:
	_top = get_parent() as Top
	top_level = true          # ignore parent transform — we draw in world space
	_imm = ImmediateMesh.new()
	mesh = _imm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.no_depth_test = true  # draw over the arena so markers stay visible
	material_override = _mat

func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	if _top == null or _top.current_state != Top.State.ACTIVE:
		_imm.clear_surfaces()
		return
		
	if _top == null or _top.current_state != Top.State.ACTIVE:
		_imm.clear_surfaces()
		return

	var y := _top.global_position.y + 0.01   # lift slightly off the surface
	#print("viz global_transform: ", global_transform)
	_imm.clear_surfaces()
	_imm.surface_begin(Mesh.PRIMITIVE_LINES)

	# Drifted pattern centre
	var centre_2d: Vector2 = _top.arena_centre + _top._centre_offset
	var centre := Vector3(centre_2d.x, y, centre_2d.y)
	_cross(centre, centre_colour)

	# Current pattern target
	var scale_now := 0.5
	var target_2d: Vector2 = centre_2d + _top.movement_pattern.get_target(
		_top._angle, scale_now, _top._rotation_phase)
	var target := Vector3(target_2d.x, y, target_2d.y)
	
	_trail.append(_top.global_position + Vector3(0, 0.01, 0))
	_target_trail.append(target)
	if _trail.size() > trail_length:
		_trail.pop_front()
		_target_trail.pop_front()
	
	_cross(target, target_colour)

	# Line from top to its target — length shows the tracking gap
	_line(_top.global_position + Vector3(0, 0.01, 0), target, target_colour)

	# Velocity vector
	var vel := Vector3(_top._velocity.x, 0, _top._velocity.y) * velocity_arrow_scale
	_line(_top.global_position + Vector3(0, 0.01, 0),
		  _top.global_position + Vector3(0, 0.01, 0) + vel, velocity_colour)
	_polyline(_trail, trail_colour)
	_polyline(_target_trail, target_trail_colour)
	
	_imm.surface_end()

	#print("top: ", _top.global_position,
		  #" centre: ", centre,
		  #" target: ", target,
		  #" arena_centre: ", _top.arena_centre)

func _cross(at: Vector3, col: Color) -> void:
	_line(at - Vector3(marker_size, 0, 0), at + Vector3(marker_size, 0, 0), col)
	_line(at - Vector3(0, 0, marker_size), at + Vector3(0, 0, marker_size), col)

func _line(from: Vector3, to: Vector3, col: Color) -> void:
	_imm.surface_set_color(col)
	_imm.surface_add_vertex(from)
	_imm.surface_set_color(col)
	_imm.surface_add_vertex(to)

func _polyline(points: Array[Vector3], col: Color) -> void:
	for i in range(1, points.size()):
		_line(points[i - 1], points[i], col)
