class_name RoundIndicator
extends Control

## Shows the current round number between the gauges, for the duration of the
## round. Distinct from the round banner, which announces and fades — this is
## orientation the viewer can glance at mid-fight.

@export var match_manager: MatchManager

@export_group("Text")
@export var font: Font
@export var font_size := 48
@export var outline_size := 6
@export var shader: Shader
@export var top_colour := Color(0.94, 0.95, 1.0)
@export var bottom_colour := Color(0.60, 0.64, 0.76)

@export_group("Layout")
## Position as a fraction of the screen, so it sits between the gauge columns
## without needing to know where they are.
@export var anchor_position := Vector2(0.5, 0.1)
@export var prefix := "ROUND "

var _label: Label
var _label_outline: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	assert(match_manager != null, "RoundIndicator: match_manager is unassigned.")
	_build()
	visible = false
	match_manager.round_starting.connect(_on_round_starting)
	match_manager.match_complete.connect(_on_match_complete)


func _build() -> void:
	# Two layers, as with the banners: Godot draws outline and fill in one
	# pass, so a gradient shader on a single Label would tint the outline too.
	_label_outline = Label.new()
	_configure(_label_outline)
	_label_outline.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_label_outline.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label_outline.add_theme_constant_override("outline_size", outline_size)
	add_child(_label_outline)

	_label = Label.new()
	_configure(_label)
	if shader != null:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("top_colour", top_colour)
		mat.set_shader_parameter("bottom_colour", bottom_colour)
		_label.material = mat
	add_child(_label)


func _configure(l: Label) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)


func _on_round_starting(round_number: int, _scores: Dictionary) -> void:
	if match_manager.rounds_to_win <= 1:
		return
	var txt = "%s%d" % [prefix, round_number]
	_label.text = txt
	_label_outline.text = txt
	visible = true
	# Positioned immediately: _process only lays out from the next frame, so
	# the labels would otherwise flash at the top-left corner first.
	_layout()


func _on_match_complete(_winners: Array[Top], _scores: Dictionary) -> void:
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	_layout()

func _layout() -> void:
	var rect = Vector2(size.x, float(font_size) * 1.5)
	var pos = Vector2(
		size.x * (anchor_position.x - 0.5),
		size.y * anchor_position.y - rect.y * 0.5
	)
	for l in [_label, _label_outline]:
		l.size = rect
		l.position = pos

	if _label.material is ShaderMaterial:
		var m: ShaderMaterial = _label.material
		var glyph_h = float(font_size)
		m.set_shader_parameter("rect_top",
			_label.global_position.y + rect.y * 0.5 - glyph_h * 0.5)
		m.set_shader_parameter("rect_height", maxf(glyph_h, 1.0))
