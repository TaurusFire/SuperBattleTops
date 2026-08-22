class_name TargetMarker
extends Node3D

## A crosshair that locks onto a top. Billboarded, so it reads as a HUD element
## pinned to the target rather than something in the world.
##
## Driven by whatever wants it — currently the kamikaze telegraph — rather than
## owning its own trigger logic, so a future ability can reuse it with a
## different colour.

@export var colour := Color(0.72, 0.32, 0.95)
@export var size := 0.04
## Size at the start of the lock-on, as a multiple of `size`. Contracting from
## large to small is what reads as acquiring a target rather than simply
## appearing.
@export var lock_start_scale := 3.0
## Seconds the contraction takes.
@export var lock_time := 0.3
## Depth of the pulse once locked, as a fraction of `size`.
@export var pulse_amount := 0.12
@export var pulse_rate := 7.0
## Height above the target's base.
@export var height_offset := 0.018
## Rotation while locking, radians. Spins in as it contracts.
@export var spin_in := 2.2

var _target: Top
var _elapsed := 0.0
var _active := false
var _committed := false

var _mesh: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE          # scaled at runtime

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Keep it readable when the target passes behind the rim.
	_material.no_depth_test = true
	_material.albedo_texture = _make_texture()
	_material.albedo_color = colour
	_material.disable_receive_shadows = true

	_mesh = MeshInstance3D.new()
	_mesh.mesh = quad
	_mesh.material_override = _material
	add_child(_mesh)


## Draws the reticle into an image: an open ring, four tick marks crossing it,
## and a centre dot. Generated rather than imported so the colour can be set
## per ability without needing a texture variant for each.
func _make_texture() -> ImageTexture:
	var res := 128
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))

	var c := float(res) * 0.5
	var ring_r := float(res) * 0.33
	var ring_w := float(res) * 0.075
	var dot_r := float(res) * 0.055
	var tick_inner := ring_r - ring_w
	var tick_outer := ring_r + ring_w * 1.9
	var tick_half := float(res) * 0.055

	for y in res:
		for x in res:
			var dx := float(x) - c
			var dy := float(y) - c
			var d := sqrt(dx * dx + dy * dy)
			var a := 0.0

			# The ring, with a gap at each tick so the marks read as separate.
			if absf(d - ring_r) < ring_w * 0.5:
				var gap = absf(dx) < tick_half or absf(dy) < tick_half
				if not gap:
					a = 1.0

			# Tick marks, crossing the ring at the four cardinals.
			if d > tick_inner and d < tick_outer:
				if absf(dx) < tick_half * 0.55 or absf(dy) < tick_half * 0.55:
					a = 1.0

			if d < dot_r:
				a = 1.0

			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))

	return ImageTexture.create_from_image(img)


## Begins tracking. Call at the moment the target is chosen.
func lock_on(target: Top, tint := Color(0, 0, 0, 0)) -> void:
	_target = target
	_elapsed = 0.0
	_active = true
	_committed = false
	if tint.a > 0.0:
		_material.albedo_color = tint
	visible = true
	set_process(true)


func release() -> void:
	_active = false
	_committed = false
	_target = null
	visible = false
	set_process(false)

func retarget(target: Top) -> void:
	if not _active:
		lock_on(target)
		return
	_target = target

func commit() -> void:
	_committed = true
	_elapsed = 0.0

func _process(delta: float) -> void:
	if not _active or _target == null \
			or _target.current_state in [Top.State.STOPPED, Top.State.KNOCKED_OUT]:
		release()
		return

	_elapsed += delta
	global_position = _target.global_position + Vector3(0.0, height_offset, 0.0)

	var lock_t = clamp(_elapsed / max(lock_time, 0.001), 0.0, 1.0)
	# Ease out, so it snaps down fast then settles — the deceleration is what
	# makes it feel like it has caught something.
	var eased := 1.0 - pow(1.0 - lock_t, 3.0)
	var s := size * lerpf(lock_start_scale, 1.0, eased)
	
	if _committed:
		s += size * pulse_amount * sin(_elapsed * pulse_rate)
	# The billboard overrides the node's basis, scale included — so the size
	# has to live on the mesh itself.
	(_mesh.mesh as QuadMesh).size = Vector2(s, s)

	_mesh.rotation.z = spin_in * (1.0 - eased)

	# Fade in over the first part of the lock rather than appearing at once.
	var col := _material.albedo_color
	col.a = clamp(lock_t * 3.0, 0.0, 1.0)
	_material.albedo_color = col
