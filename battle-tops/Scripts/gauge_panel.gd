class_name GaugePanel
extends CanvasLayer

## Spawns one RPM gauge per top in the manager, positioned in the corners.
## Tops are the source of truth: add or remove one from the manager's array
## and the gauges follow.

@export var manager: GameManager
@export var gauge_scene: PackedScene
@export var gauge_size := Vector2(180, 180)
## Inset from the screen edges.
## Horizontal inset for the first row.
@export var margin_x_top := 188.0
## Horizontal inset for rows below the first. Larger values pull the lower
## gauges inward, away from the screen edges.
@export var margin_x_lower := 78.0
## Distance from the top of the screen.
@export var margin_y := 180.0
@export var row_spacing := 75.0
@export var mirror_right_half := true
## Corner order gauges are assigned to, as anchor pairs.


var _gauges: Array[RPMGauge] = []

func _ready() -> void:
	assert(manager != null, "GaugePanel needs the manager assigned.")
	_rebuild()

func _rebuild() -> void:
	for g in _gauges:
		g.queue_free()
	_gauges.clear()

	var valid: Array[Top] = []
	for t in manager.tops:
		if t != null:
			valid.append(t)

	for i in valid.size():
		# Even indices go left, odd go right; each pair starts a new row.
		var is_right := (i % 2) == 1
		var row := i / 2
		_gauges.append(_make_gauge(valid[i], is_right, row))


func _make_gauge(top: Top, is_right: bool, row: int) -> RPMGauge:
	var g: RPMGauge = gauge_scene.instantiate()

	g.top = top
	g.mirrored = is_right
	if top.spin_visual != null:
		g.model_mesh = top.spin_visual.mesh
		var mats: Array[Material] = []
		for i in top.spin_visual.get_surface_override_material_count():
			mats.append(top.spin_visual.get_surface_override_material(i))
		g.model_materials = mats
	
	add_child(g)

	var side := 1.0 if is_right else 0.0
	g.anchor_left = side
	g.anchor_right = side
	g.anchor_top = 0.0
	g.anchor_bottom = 0.0

	var inset := margin_x_top if row == 0 else margin_x_lower
	var x := inset if not is_right else -(gauge_size.x + inset)
	var y := margin_y + row * (gauge_size.y + row_spacing)

	g.offset_left = x
	g.offset_right = x + gauge_size.x
	g.offset_top = y
	g.offset_bottom = y + gauge_size.y

	return g
