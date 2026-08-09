class_name BannerText
extends Control

## Big centred text that punches in oversized then settles. Used for both the
## countdown and the result — it knows nothing about either, it just displays
## whatever it's handed.

@export_group("Text")
@export var font: Font
@export var font_size := 220
@export var outline_size := 18

@export_group("Colours")
@export var shader: Shader
@export var top_colour := Color(0.95, 0.22, 0.16)
@export var bottom_colour := Color(1.0, 0.78, 0.35)
@export var outline_colour := Color(0, 0, 0)

@export_group("Animation")
@export var punch_scale := 2.2
@export var punch_speed := 9.0
@export var fade_time := 0.28



var _label: Label
var _label_outline: Label
var _scale := 1.0
var _alpha := 0.0
var _timer := 0.0
var _active_hold := 0.0
var _settle_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_labels()


## Show `text` for `hold` seconds, settling at `settle_scale` after the punch.
## Pass `size_override` to use a different font size for this message.
func show_text(text: String, hold: float, settle_scale := 1.0,
			   size_override := -1) -> void:
	var s := size_override if size_override > 0 else font_size
	for l in [_label, _label_outline]:
		l.text = text
		l.add_theme_font_size_override("font_size", s)
	_settle_scale = settle_scale
	_scale = punch_scale
	_alpha = 1.0
	_timer = 0.0
	_active_hold = hold
	visible = true


func _build_labels() -> void:
	_label_outline = Label.new()
	_configure(_label_outline)
	_label_outline.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_label_outline.add_theme_color_override("font_outline_color", outline_colour)
	_label_outline.add_theme_constant_override("outline_size", outline_size)
	add_child(_label_outline)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 220)
	_configure(_label)
	
	if shader != null:
		var mat := ShaderMaterial.new()
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


func _process(delta: float) -> void:
	if not visible:
		return

	_timer += delta
	_scale = lerpf(_scale, _settle_scale, clamp(punch_speed * delta, 0.0, 1.0))

	var fade_start := _active_hold - fade_time
	if _timer > fade_start:
		_alpha = clamp(1.0 - (_timer - fade_start) / fade_time, 0.0, 1.0)
	if _timer >= _active_hold:
		visible = false
		return

	_apply()


func _apply() -> void:
	var rect := Vector2(size.x, float(_label.get_theme_font_size("font_size")) * 1.5)
	var pos := Vector2(0.0, size.y * 0.5 - rect.y * 0.5)

	for l in [_label, _label_outline]:
		l.size = rect
		l.position = pos
		l.pivot_offset = rect * 0.5
		l.scale = Vector2(_scale, _scale)
		l.modulate.a = _alpha

	if _label.material is ShaderMaterial:
		var m: ShaderMaterial = _label.material
		# Map the gradient across the glyphs rather than the whole rect, which
		# is taller than the text and would compress the visible range.
		var glyph_h := float(_label.get_theme_font_size("font_size")) * _scale
		var centre_y := _label.global_position.y + rect.y * 0.5 * _scale
		m.set_shader_parameter("rect_top", centre_y - glyph_h * 0.5)
		m.set_shader_parameter("rect_height", maxf(glyph_h, 1.0))


func set_colours(top_col: Color, bottom_col: Color) -> void:
	if _label.material is ShaderMaterial:
		var m: ShaderMaterial = _label.material
		m.set_shader_parameter("top_colour", top_col)
		m.set_shader_parameter("bottom_colour", bottom_col)
	else:
		_label.add_theme_color_override("font_color", top_col)
