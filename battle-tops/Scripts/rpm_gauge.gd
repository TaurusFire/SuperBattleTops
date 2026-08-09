class_name RPMGauge
extends Control

## A radial RPM gauge: an arc whose fill tracks the top's remaining spin, with
## a red chip bar that lingers after a hit before draining, and the top's own
## mesh rendered live in the middle.
##
## The colour gradient is fixed *along the arc*, not driven by the current
## value — so the low end is always red and the full end always green, and a
## depleting bar retreats into the red rather than changing hue as a whole.

@export var top: Top

@export_group("Name")
@export var show_name := true
@export var name_font: Font
@export var name_size := 36
@export var name_outline_size := 15
## Vertical offset from the gauge centre. Negative sits above the arc.
@export var name_y_offset := -120.0
var _name_label: Label
var _name_outline: Label

@export_group("Arc")
## Where the arc begins, in degrees. 0 is to the right, increasing clockwise.
@export var arc_start_degrees := 90.0
## How far it sweeps. 260 leaves a gap at the bottom for the readout.
@export var arc_sweep_degrees := -245.0
@export var radius := 90.0
@export var thickness := 30.0
## Flip the sweep, so gauges on the right of the screen mirror those on the left.
@export var mirrored := false
## Arc smoothness. Higher costs more but curves better at large radii.
@export var segments := 	12
## Thickness at the empty end, as a fraction of `thickness`. Below 1 the arc
## tapers, widening toward full.
@export_range(0.2, 1.5) var taper_start := 0.55
## Thickness at the full end.
@export_range(0.2, 1.5) var taper_end := 1.5
## Angle of the cut at each end, in degrees of arc. 0 is square.
@export var end_angle_degrees := 0.0
## How far the outline extends past each end of the arc, in degrees.
@export var outline_cap_degrees := 5

@export_group("Chip Damage")
## Seconds the red bar holds before it starts draining.
@export var chip_delay := 0.35
## How fast the red catches up, in ratio per second.
@export var chip_drain_speed := 0.55
## A drop larger than this counts as a hit and restarts the delay. Below it,
## the red simply trails the continuous RPM decay.
@export var hit_threshold := 0.005

@export_group("Colours")
@export var gradient: Gradient
@export var track_colour := Color(0.07, 0.08, 0.10, 0.9)
@export var chip_colour := Color(0.86, 0.16, 0.13)
@export var outline_colour := Color(0.03, 0.03, 0.04, 0.95)
@export var outline_width := 6.0

@export_group("Model")
@export var model_mesh: Mesh
## Surface overrides, since materials assigned on the world MeshInstance3D
## don't travel with the Mesh resource itself.
@export var model_materials: Array[Material] = []
@export var model_pixels := 175
@export var model_spin_speed := 2.4
@export var model_tilt_degrees := -20.0
## Orthogonal camera extent. Smaller frames the top more tightly.
@export var model_zoom := 0.062

@export_group("Readout")
@export var show_readout := true
@export var readout_font: Font
@export var readout_size := 40
@export var readout_colour := Color(1, 1, 1)
@export var readout_shader: Shader
@export var readout_top_colour := Color(0.997, 0.84, 0.0, 1.0)
@export var readout_bottom_colour := Color(0.0, 0.672, 0.739, 1.0)
@export var readout_outline_size := 12
@export_range(0.2, 1.0) var rpm_text_scale := 0.45
@export var rpm_text_offset := Vector2(1.0, -3.0)
var _label_outline: Label
var _rpm_caption: Label
var _rpm_caption_outline: Label

@export_group("Bevel")
@export var bevel_enabled := true
## Fraction of the band's thickness taken by the highlight.
@export_range(0.0, 0.6) var bevel_fraction := 0.3
@export var bevel_colour := Color(1, 1, 1, 0.28)

@export_group("Leading Edge")
@export var glow_enabled := true
## How far the glow extends back along the arc, as a fraction of the sweep.
@export_range(0.0, 0.3) var glow_length := 0.08
## Thickness multiplier at the head, so the glow bulges slightly.
@export_range(1.0, 2.0) var glow_swell := 1.1
@export var glow_colour := Color(1.0, 1.0, 0.92, 0.85)

@export_group("Ability Marker")
@export var marker_enabled := true
@export var marker_colour := Color(1.0, 0.85, 0.25)
## Width of the tick, in degrees of arc.
@export var marker_width_degrees := 3.5
## How far the tick overhangs the band on each side.
@export var marker_overhang := 5.0
@export var marker_outline := Color(0, 0, 0, 0.9)

var _fill := 1.0
var _chip := 1.0
var _chip_timer := 0.0
var _prev_fill := 1.0

var _viewport: SubViewport
var _model: MeshInstance3D
var _model_rect: TextureRect
var _label: Label


func _ready() -> void:
	if gradient == null:
		gradient = _default_gradient()
	_build_model_viewport()
	if show_readout:
		_build_readout()
	if show_name:
		_build_name()
	if top != null:
		_fill = top.rpm_ratio
		_chip = _fill
		_prev_fill = _fill

func _configure_name(l: Label) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f: Font = name_font if name_font != null else readout_font
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", name_size)

func _build_name() -> void:
	var base := Color(1, 1, 1)
	var second := Color(0, 0, 0, 0)
	if top != null and top.stats != null:
		base = top.stats.name_colour
		second = top.stats.name_colour_secondary

	_name_outline = Label.new()
	_configure_name(_name_outline)
	_name_outline.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_name_outline.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_name_outline.add_theme_constant_override("outline_size", name_outline_size)
	add_child(_name_outline)

	_name_label = Label.new()
	_configure_name(_name_label)

	if second.a > 0.001 and readout_shader != null:
		# Two colours given: gradient fill, top to bottom.
		var mat := ShaderMaterial.new()
		mat.shader = readout_shader
		mat.set_shader_parameter("top_colour", base)
		mat.set_shader_parameter("bottom_colour", second)
		_name_label.material = mat
	else:
		# One colour: flat fill, no shader needed.
		_name_label.add_theme_color_override("font_color", base)

	add_child(_name_label)

	var txt := top.display_name().to_upper() if top != null else ""
	_name_label.text = txt
	_name_outline.text = txt
	

func _default_gradient() -> Gradient:
	# Red at the empty end, green at the full end.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.34, 0.62, 1.0])
	g.colors = PackedColorArray([
		Color(0.86, 0.16, 0.12),   # red
		Color(0.94, 0.52, 0.14),   # orange
		Color(0.95, 0.84, 0.20),   # yellow
		Color(0.36, 0.82, 0.32),   # green
	])
	return g


func _build_model_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(model_pixels, model_pixels)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_viewport.world_3d = World3D.new()
	add_child(_viewport)

	var pivot := Node3D.new()
	if not mirrored:
		pivot.rotation_degrees = Vector3(10.0, 0.0, model_tilt_degrees)
	else:
		pivot.rotation_degrees = Vector3(10.0, 0.0, -model_tilt_degrees)
	_viewport.add_child(pivot)

	_model = MeshInstance3D.new()
	_model.mesh = model_mesh
	for i in model_materials.size():
		_model.set_surface_override_material(i, model_materials[i])
	pivot.add_child(_model)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = model_zoom
	cam.position = Vector3(0.0, 0.030, 0.075)
	_viewport.add_child(cam)
	cam.look_at(Vector3(0.0, 0.012, 0.0), Vector3.UP)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	key.light_energy = 1.3
	_viewport.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.75, 0.85, 1.0)
	_viewport.add_child(rim)

	_model_rect = TextureRect.new()
	_model_rect.texture = _viewport.get_texture()
	_model_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_model_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_model_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_model_rect)

func _configure_label(l: Label) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if readout_font != null:
		l.add_theme_font_override("font", readout_font)
	l.add_theme_font_size_override("font_size", readout_size)
	
func _build_readout() -> void:
	# Two stacked Labels: Godot draws outline and fill in a single pass from
	# the same texture, so a shader on one hits both. Separating them lets the
	# gradient apply to the fill while the outline stays black.

	# Outline layer, added first so it renders behind.
	_label_outline = Label.new()
	_configure_label(_label_outline)
	_label_outline.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_label_outline.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label_outline.add_theme_constant_override("outline_size", readout_outline_size)
	add_child(_label_outline)

	# Fill layer, carrying the gradient.
	_label = Label.new()
	_configure_label(_label)
	if readout_shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = readout_shader
		mat.set_shader_parameter("top_colour", readout_top_colour)
		mat.set_shader_parameter("bottom_colour", readout_bottom_colour)
		_label.material = mat
	add_child(_label)
	
	_rpm_caption_outline = Label.new()
	_configure_caption(_rpm_caption_outline)
	_rpm_caption_outline.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_rpm_caption_outline.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_rpm_caption_outline.add_theme_constant_override(
		"outline_size", int(readout_outline_size * rpm_text_scale))
	add_child(_rpm_caption_outline)
	
	_rpm_caption = Label.new()
	_configure_caption(_rpm_caption)
	if readout_shader != null:
		var cap_mat := ShaderMaterial.new()
		cap_mat.shader = readout_shader
		cap_mat.set_shader_parameter("top_colour", readout_top_colour)
		cap_mat.set_shader_parameter("bottom_colour", readout_bottom_colour)
		_rpm_caption.material = cap_mat
	add_child(_rpm_caption)

func _process(delta: float) -> void:
	if top == null:
		return

	_fill = clamp(top.rpm_ratio, 0.0, 1.0)

	# A sharp drop is a hit: hold the red where it was, then let it drain.
	var drop := _prev_fill - _fill
	if drop > hit_threshold:
		_chip_timer = chip_delay
	_prev_fill = _fill

	if _chip < _fill:
		_chip = _fill                      # RPM went up somehow; snap.
	elif _chip > _fill:
		if _chip_timer > 0.0:
			_chip_timer -= delta
		else:
			_chip = max(_chip - chip_drain_speed * delta, _fill)

	if _model != null:
		# Spin proportional to remaining RPM, so a dying top visibly slows.
		_model.rotate_y(-model_spin_speed * max(_fill, 0.05) * delta)

	_layout()
	if _label != null:
		var txt := str(int(round(top.current_rpm)))
		_label.text = txt
		_label_outline.text = txt
		if _label.material is ShaderMaterial:
			var m: ShaderMaterial = _label.material
			m.set_shader_parameter("rect_top", _label.global_position.y)
			m.set_shader_parameter("rect_height", maxf(_label.size.y, 1.0))

	queue_redraw()


func _layout() -> void:
	var c := size * 0.5
	var m := float(model_pixels)
	var num_size := Vector2(size.x, float(readout_size) * 1.4)
	var pos := Vector2(40.0 if mirrored else -40.0, c.y + radius * 0.34)
	
	if _model_rect != null:
		_model_rect.size = Vector2(m, m)
		_model_rect.position = c - Vector2(m, m) * 0.5
	
	if _name_label != null:
		var n_rect := Vector2(size.x, float(name_size) * 1.5)
		var n_pos := Vector2(0.0, c.y + name_y_offset - n_rect.y * 0.5)
		_name_label.size = n_rect
		_name_label.position = n_pos
		_name_outline.size = n_rect
		_name_outline.position = n_pos

		if _name_label.material is ShaderMaterial:
			var nm: ShaderMaterial = _name_label.material
			var glyph_h := float(name_size)
			nm.set_shader_parameter("rect_top",
				_name_label.global_position.y + n_rect.y * 0.5 - glyph_h * 0.5)
			nm.set_shader_parameter("rect_height", maxf(glyph_h, 1.0))
			
		
	if _label != null:
		var w := size.x
		var h := float(readout_size) * 1.4
		_label.size = Vector2(w, h)
		_label.position = pos
		_label_outline.size = Vector2(w, h)
		_label_outline.position = pos

	if _rpm_caption == null:
		return

	# Caption sits against the number's near edge, on the side facing the
	# centre of the screen, so it never runs off the outer edge of frame.
	var font: Font = readout_font if readout_font != null \
		else _label.get_theme_font("font")
	var num_w := font.get_string_size(
		_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, readout_size).x

	# The number's glyphs are centred on its own Label, not on the gauge.
	var num_centre_x := pos.x + num_size.x * 0.5
	var cap_w := 60.0
	var cap_x: float
	if mirrored:
		# Right-hand gauge: caption to the right of the number.
		cap_x = num_centre_x + num_w * 0.5 + rpm_text_offset.x
		_rpm_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		# Left-hand gauge: caption to the left of the number.
		cap_x = num_centre_x - num_w * 0.5 - cap_w - rpm_text_offset.x
		_rpm_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rpm_caption_outline.horizontal_alignment = _rpm_caption.horizontal_alignment

	var cap_size := Vector2(cap_w, float(readout_size) * rpm_text_scale * 1.4)
	var cap_pos := Vector2(cap_x, pos.y + rpm_text_offset.y)
	_rpm_caption.size = cap_size
	_rpm_caption.position = cap_pos
	_rpm_caption_outline.size = cap_size
	_rpm_caption_outline.position = cap_pos
		

func _draw() -> void:

	var c := size * 0.5
	var a0 := deg_to_rad(arc_start_degrees)
	var sweep := deg_to_rad(arc_sweep_degrees)
	if mirrored:
		a0 = deg_to_rad(180.0 - arc_start_degrees)
		sweep = -sweep
	var half := thickness * 0.5
	
	
	# Outline: same band, fatter, and extended past both ends so it wraps
	# around the caps rather than stopping flush with them.
	var cap := deg_to_rad(outline_cap_degrees) * signf(sweep)
	_band(c, radius, half + outline_width, a0 - cap, sweep + cap * 2.0, 1.0,
		  func(_t): return outline_colour)

	_band(c, radius, half, a0, sweep, 1.0, func(_t): return track_colour)
	
	if _chip > _fill + 0.001:
		_band(c, radius, half, a0, sweep, _chip, func(_t): return chip_colour)

	if _fill > 0.001:
		_band(c, radius, half, a0, sweep, _fill,
			  func(t): return gradient.sample(t * _fill))

		# Bevel: a strip along the outer edge of the fill, suggesting a raised
		# surface. Drawn last so it sits over the gradient.
		if bevel_enabled:
			_band(c, radius, half, a0, sweep, _fill,
				  func(_t): return bevel_colour,
				  1.0 - bevel_fraction, 1.0)
		if glow_enabled:
			_draw_leading_glow(c, a0, sweep, half)
	
	if marker_enabled and top != null and top.ability != null:
		var frac = top.ability.gauge_marker(top)
		if frac > 0.0 and frac < 1.0:
			_draw_marker(c, a0, sweep, half, frac)

## A short, swollen, fading cap at the head of the fill, so the current value
## has a defined leading edge rather than simply stopping.
func _draw_leading_glow(centre: Vector2, from_angle: float,
						sweep: float, half_thick: float) -> void:
	var tail := maxf(_fill - glow_length, 0.0)
	var span := _fill - tail
	if span <= 0.001:
		return

	var steps = max(int(ceil(segments * span)), 3)
	for i in steps:
		var u0 = float(i) / steps          # 0 at the tail, 1 at the head
		var u1 = float(i + 1) / steps

		var t0 = tail + span * u0
		var t1 = tail + span * u1
		var ang0 = from_angle + sweep * t0
		var ang1 = from_angle + sweep * t1

		# Swell toward the head, and fade out toward the tail.
		var s0 := lerpf(1.0, glow_swell, u0)
		var s1 := lerpf(1.0, glow_swell, u1)
		var w0 := half_thick * lerpf(taper_start, taper_end, t0) * s0
		var w1 := half_thick * lerpf(taper_start, taper_end, t1) * s1

		var c0 := glow_colour
		var c1 := glow_colour
		c0.a *= u0 * u0
		c1.a *= u1 * u1

		var d0 := Vector2(cos(ang0), sin(ang0))
		var d1 := Vector2(cos(ang1), sin(ang1))

		# Match the fill band's chamfer, so the glow's head lines up with the
		# angled cut rather than stopping square behind it.
		var e1 := d1
		if i == steps - 1 and end_angle_degrees != 0.0:
			var seg_angle = absf(sweep * span) / steps
			var chamfer := minf(deg_to_rad(end_angle_degrees), seg_angle * 0.9) * signf(sweep)
			var a = ang1 - chamfer
			e1 = Vector2(cos(a), sin(a))

		draw_polygon(
			PackedVector2Array([
				centre + d0 * (radius - w0),
				centre + d0 * (radius + w0),
				centre + e1 * (radius + w1),
				centre + d1 * (radius - w1),
			]),
			PackedColorArray([c0, c0, c1, c1])
		)

## Draws an annular band from the arc start through `portion` of the sweep.
## `colour_fn` receives 0..1 along the drawn portion.
##
## `radial_lo`/`radial_hi` are fractions across the band's thickness, so a
## bevel can be drawn as a thin strip of the same tapered shape rather than
## a separate arc that wouldn't follow the taper.
func _band(centre: Vector2, r_mid: float, half_thick: float,
		   from_angle: float, sweep: float, portion: float,
		   colour_fn: Callable,
		   radial_lo: float = 0.0, radial_hi: float = 1.0) -> void:
	if portion <= 0.0:
		return
	var steps = max(int(ceil(segments * portion)), 2)
	var seg_angle = absf(sweep * portion) / steps
	var chamfer := minf(deg_to_rad(end_angle_degrees), seg_angle * 0.9) * signf(sweep)

	for i in steps:
		var t0 = float(i) / steps
		var t1 = float(i + 1) / steps

		var ang0 = from_angle + sweep * portion * t0
		var ang1 = from_angle + sweep * portion * t1

		# Thickness at each end of this segment, following the taper across
		# the whole arc rather than just the drawn portion.
		var w0 := half_thick * lerpf(taper_start, taper_end, t0 * portion)
		var w1 := half_thick * lerpf(taper_start, taper_end, t1 * portion)

		var d0 := Vector2(cos(ang0), sin(ang0))
		var d1 := Vector2(cos(ang1), sin(ang1))

		# Chamfer: shift the outer corner along the arc at the two ends, so
		# the cut is angled instead of square.
		var e0 := d0
		var e1 := d1
		if i == 0 and end_angle_degrees != 0.0:
			var a = ang0 + chamfer
			e0 = Vector2(cos(a), sin(a))
		if i == steps - 1 and end_angle_degrees != 0.0:
			var a = ang1 - chamfer
			e1 = Vector2(cos(a), sin(a))

		var lo0 := r_mid - w0 + w0 * 2.0 * radial_lo
		var hi0 := r_mid - w0 + w0 * 2.0 * radial_hi
		var lo1 := r_mid - w1 + w1 * 2.0 * radial_lo
		var hi1 := r_mid - w1 + w1 * 2.0 * radial_hi

		var c0: Color = colour_fn.call(t0)
		var c1: Color = colour_fn.call(t1)

		draw_polygon(
			PackedVector2Array([
				centre + d0 * lo0,
				centre + e0 * hi0,
				centre + e1 * hi1,
				centre + d1 * lo1,
			]),
			PackedColorArray([c0, c0, c1, c1])
		)

## A thin arc outside the main band, overhanging its ends so the gauge reads
## as sitting in a housing.

func _configure_caption(l: Label) -> void:
	l.text = "RPM"
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if readout_font != null:
		l.add_theme_font_override("font", readout_font)
	l.add_theme_font_size_override("font_size", int(readout_size * rpm_text_scale))

## A tick across the arc at `frac` along the sweep, marking where an ability
## will fire. Drawn as its own small band so it follows the taper and the
## chamfer the same way the fill does.
func _draw_marker(centre: Vector2, from_angle: float, sweep: float,
				  half_thick: float, frac: float) -> void:
	var half_w := deg_to_rad(marker_width_degrees) * 0.5
	var mid := from_angle + sweep * frac
	var w := half_thick * lerpf(taper_start, taper_end, frac) + marker_overhang

	var steps := 4
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var ang0 := mid - half_w + half_w * 2.0 * t0
		var ang1 := mid - half_w + half_w * 2.0 * t1
		var d0 := Vector2(cos(ang0), sin(ang0))
		var d1 := Vector2(cos(ang1), sin(ang1))
		# Outline first, then the tick inside it.
		draw_polygon(
			PackedVector2Array([
				centre + d0 * (radius - w - 2.0),
				centre + d0 * (radius + w + 2.0),
				centre + d1 * (radius + w + 2.0),
				centre + d1 * (radius - w - 2.0),
			]),
			PackedColorArray([marker_outline, marker_outline, marker_outline, marker_outline])
		)
		draw_polygon(
			PackedVector2Array([
				centre + d0 * (radius - w),
				centre + d0 * (radius + w),
				centre + d1 * (radius + w),
				centre + d1 * (radius - w),
			]),
			PackedColorArray([marker_colour, marker_colour, marker_colour, marker_colour])
		)
