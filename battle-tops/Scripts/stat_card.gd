class_name StatCard
extends Control

## Shows a fighter's name and star ratings while it flies past the camera
## during the intro. Listens to the sequencer rather than being driven by it,
## so the 3D choreography and the 2D card stay separate.

@export var intro: IntroSequence
@export var config: StatDisplayConfig
var _anchor := Vector2.ZERO


@export_group('Layout')
## Which side of the frame the card sits on, matching the fighter's gauge.
@export var side_margin = 60.0
@export var vertical_centre = 0.62
@export var row_height = 46.0
@export var label_width = 150.0

@export_group('Style')
@export var font: Font
@export var name_size = 54
@export var label_size = 24
@export var outline_size = 6
@export var star_size = 22.0
@export var star_gap = 6.0
@export var star_filled = Color(1.0, 0.84, 0.28)
@export var star_empty = Color(0.28, 0.29, 0.33, 0.85)
@export var star_outline = Color(0, 0, 0, 0.9)
@export var label_colour = Color(0.88, 0.90, 0.94)

@export_group('Animation')
@export var fade_in = 0.12
@export var fade_out = 0.18
## How far the card slides in from its side, in pixels.
@export var slide = 70.0

@export var camera: Camera3D
@export_group('Layout')
## Horizontal gap between the top and the card, in pixels.
@export var card_gap := 90.0
@export var card_width := 340.0


var _top: Top
var _ratings: Array = []          # [{label, stars}]
var _alpha = 0.0
var _target_alpha = 0.0
var _slide_amount = 1.0
var _right_side = false

var _name_label: Label
var _name_outline: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_name()
	if intro != null:
		intro.top_introduced.connect(_on_introduced)
		intro.top_departed.connect(_on_departed)


func _build_name() -> void:
	# Two layers, as elsewhere: Godot draws outline and fill in one pass, so a
	# gradient on a single Label would tint the outline too.
	_name_outline = Label.new()
	_configure_name(_name_outline)
	_name_outline.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_name_outline.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_name_outline.add_theme_constant_override("outline_size", outline_size)
	add_child(_name_outline)

	_name_label = Label.new()
	_configure_name(_name_label)
	add_child(_name_label)


func _configure_name(l: Label) -> void:
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", name_size)


func _on_introduced(top: Top, index: int) -> void:
	_top = top
	_right_side = (index % 2) == 1
	_ratings = _rate_all(top)
	# Captured once: the card marks where the top was when it reached the
	# apex, rather than tracking it as it moves on.
	_anchor = _compute_anchor(top)

	var txt = top.display_name().to_upper()
	_name_label.text = txt
	_name_outline.text = txt
	_name_label.add_theme_color_override("font_color", top.stats.name_colour)
	_name_label.horizontal_alignment = \
		HORIZONTAL_ALIGNMENT_LEFT if _right_side else HORIZONTAL_ALIGNMENT_RIGHT
	_name_outline.horizontal_alignment = _name_label.horizontal_alignment

	_target_alpha = 1.0


func _on_departed(_top: Top, _index: int) -> void:
	_target_alpha = 0.0


## Reads each configured stat off the fighter and converts it to half-stars.
func _rate_all(top: Top) -> Array:
	var out = []
	if config == null:
		return out
	for e in config.entries:
		if e == null:
			continue
		var raw: float = top.stats.get(e.stat_property) if e.stat_property in top.stats else 0.0
		# Some stats are better when lower — decay rate, for instance — so
		# rate the distance below a baseline instead of the value itself.
		var value: float = (e.invert_baseline - raw) if e.invert else raw
		out.append({
			"label": e.label,
			"stars": StatDisplayConfig.rate(max(value, 0.0), e.per_half_star, e.max_stars),
			"max": e.max_stars,
		})
	return out


func _process(delta: float) -> void:
	var rate = (1.0 / max(fade_in, 0.001)) if _target_alpha > _alpha \
		else (1.0 / max(fade_out, 0.001))
	_alpha = move_toward(_alpha, _target_alpha, rate * delta)
	# Slide settles as it fades in, and returns as it fades out.
	_slide_amount = 1.0 - _alpha

	if _alpha <= 0.001 and _top == null:
		return
	_layout()
	queue_redraw()


func _layout() -> void:
	if _name_label == null:
		return
	var anchor := _anchor
	var x = anchor.x + _slide_amount * slide * (-1.0 if _right_side else 1.0)
	var y = anchor.y - float(name_size) * 1.2
	var w = 340.0

	var rect = Vector2(w, float(name_size) * 1.3)
	for l in [_name_label, _name_outline]:
		l.size = rect
		l.position = Vector2(x, y)
		l.modulate.a = _alpha


func _draw() -> void:
	if _alpha <= 0.001 or _ratings.is_empty():
		return

	var anchor := _anchor
	var x = anchor.x + _slide_amount * slide * (-1.0 if _right_side else 1.0)
	var y = anchor.y - float(name_size) * 1.2

	var f: Font = font if font != null else ThemeDB.fallback_font

	for row in _ratings:
		var label_pos = Vector2(x, y + star_size * 0.9)
		var col = label_colour
		col.a *= _alpha
		f.draw_string(get_canvas_item(), label_pos, row["label"],
			HORIZONTAL_ALIGNMENT_LEFT, label_width, label_size, col)

		_draw_stars(Vector2(x + label_width, y), row["stars"], row["max"])
		y += row_height


## Half-star resolution: each star is drawn empty, then filled fully or by its
## left half depending on the rating.
func _draw_stars(at: Vector2, stars: float, max_stars: int) -> void:
	for i in max_stars:
		var centre = at + Vector2(i * (star_size + star_gap) + star_size * 0.5,
								   star_size * 0.5)
		var remaining = stars - float(i)

		var empty = star_empty
		empty.a *= _alpha
		_star(centre, star_size * 0.5, empty, 1.0)

		if remaining >= 1.0:
			var full = star_filled
			full.a *= _alpha
			_star(centre, star_size * 0.5, full, 1.0)
		elif remaining >= 0.5:
			var half = star_filled
			half.a *= _alpha
			_star(centre, star_size * 0.5, half, 0.5)


## Draws a five-pointed star, optionally clipped to its left `fraction`.
func _star(centre: Vector2, r: float, col: Color, fraction: float) -> void:
	var pts = PackedVector2Array()
	for i in 10:
		var ang = -PI * 0.5 + PI * float(i) / 5.0
		var rad = r if (i % 2 == 0) else r * 0.42
		var p = centre + Vector2(cos(ang), sin(ang)) * rad
		if fraction < 1.0:
			# Clip to the left half by pulling any right-hand point back to
			# the centre line — cheap, and reads correctly at this size.
			p.x = min(p.x, centre.x)
		pts.append(p)
	draw_colored_polygon(pts, col)


func _screen_anchor() -> Vector2:
	if _top == null or camera == null:
		return Vector2(side_margin, size.y * vertical_centre)
	var p := camera.unproject_position(_top.global_position)
	# Sit on the opposite side of the top from the frame edge it's heading to,
	# so the card never runs off screen.
	var x := (p.x - card_width - card_gap) if _right_side else (p.x + card_gap)
	return Vector2(clamp(x, side_margin, size.x - card_width - side_margin), p.y)
	
func _compute_anchor(top: Top) -> Vector2:
	if top == null or camera == null:
		return Vector2(side_margin, size.y * vertical_centre)

	# A point behind the lens unprojects to a mirrored position, so fall back
	# rather than placing the card somewhere nonsensical.
	var local := camera.global_transform.affine_inverse() * top.global_position
	if local.z > -0.001:
		return Vector2(side_margin, size.y * vertical_centre)

	var p := camera.unproject_position(top.global_position)
	var x := (p.x + card_gap) if _right_side else (p.x - card_width - card_gap)
	var card_h = float(name_size) * 1.3 + row_height * max(_ratings.size(), 1)
	return Vector2(
		clamp(x, side_margin, size.x - card_width - side_margin),
		clamp(p.y, card_h * 0.5 + 20.0, size.y - card_h * 0.5 - 20.0)
	)
