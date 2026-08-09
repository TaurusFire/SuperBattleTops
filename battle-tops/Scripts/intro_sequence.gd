class_name IntroSequence
extends Node

## Choreographs the pre-match fly-in. Each top arcs in from behind the camera
## on the side opposite its gauge, passes close to the lens where its stats can
## be read, then crosses to hover above its spawn position on its gauge side.
##
## The crossing matters: a viewer forgets where a top entered within a second,
## but remembers where it settled — and that's the position its gauge occupies
## for the rest of the match.

signal top_introduced(top: Top, index: int)
signal top_departed(top: Top, index: int)
signal finished

@export var manager: GameManager
@export var arena: Arena
@export var camera: BattleCamera

@export_group('Timing')
## Seconds arcing in from behind the camera to the apex.
@export var approach_time := 0.5
## Seconds held near the lens while the stats are readable.
@export var hold_time := 0.5
## Seconds travelling from the apex out to the hover point.
@export var depart_time := 0.5
## How far into one top's departure the next begins its approach. At 0 they're
## strictly sequential; at 1 the next arrives as this one leaves the apex.
@export_range(0.0, 1.0) var overlap := 0.8
## Stillness after the last top settles, before the countdown starts.
@export var settle_time := 0.4

@export_group('Path')
## Distance in front of the camera at the apex. Small enough to fill frame.
@export var apex_distance := 0.12
## Sideways offset at the apex, toward the top's gauge side.
@export var apex_lateral := 0.05
## How high above the camera's look direction the apex sits.
@export var apex_lift := 0.01
## How far behind the camera the top starts.
@export var start_behind := 0.25
## Sideways offset at the start, on the side opposite the gauge.
@export var start_lateral := 0.22
## Bulge of the arc between apex and hover point.
@export var arc_bow := 0.09

@export_group('Orientation')
## Tilt at the apex, radians, so the top's face is toward the camera.
@export var apex_tilt := 0.9

var _running := false
var _elapsed := 0.0
var _entries: Array[Dictionary] = []


func _ready() -> void:
	set_process(false)


## Called by the manager. Tops must already be arranged at their spawn ring
## positions — those are the destinations.
func begin() -> void:
	_entries.clear()
	var step := approach_time + hold_time + depart_time * (1.0 - overlap)

	for i in manager.tops.size():
		var top: Top = manager.tops[i]
		if top == null:
			continue
		# Even indices sit left, odd right, matching the gauge panel's layout.
		# Alternating the entry side as well stops every fly-in looking the same.
		var gauge_right := (i % 2) == 1
		_entries.append({
			"top": top,
			"index": i,
			"start_time": i * step,
			"gauge_right": gauge_right,
			"home": top.global_position,
			"announced": false,
			"departed": false,
		})

	_elapsed = 0.0
	_running = true
	set_process(true)


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta

	var all_done := true
	for e in _entries:
		if _advance(e):
			all_done = false

	if all_done and _elapsed > _total_time():
		_running = false
		set_process(false)
		finished.emit()


func _total_time() -> float:
	if _entries.is_empty():
		return settle_time
	var last: Dictionary = _entries[-1]
	return last["start_time"] + approach_time + hold_time + depart_time + settle_time


## Positions one top for the current moment. Returns true while it's still
## moving; false once it has settled at its hover point.
func _advance(e: Dictionary) -> bool:
	var top: Top = e["top"]
	var t: float = _elapsed - e["start_time"]

	if t < 0.0:
		# Not yet entered — park it out of sight behind the camera.
		top.global_position = _start_point(e)
		return true

	var apex := _apex_point(e)

	if t < approach_time:
		var u := t / approach_time
		# Ease out, so it decelerates into the hold rather than arriving flat.
		var eased := 1.0 - pow(1.0 - u, 3.0)
		top.global_position = _start_point(e).lerp(apex, eased)
		_set_tilt(top, apex_tilt * eased)
		return true

	if t < approach_time + hold_time:
		if not e["announced"]:
			e["announced"] = true
			top_introduced.emit(top, e["index"])
		# Drift very slightly through the hold, so it isn't frozen on screen.
		var u := (t - approach_time) / hold_time
		top.global_position = apex + _apex_drift(e) * u
		_set_tilt(top, apex_tilt)
		return true

	if t < approach_time + hold_time + depart_time:
		if not e["departed"]:
			e["departed"] = true
			top_departed.emit(top, e["index"])
		var u := (t - approach_time - hold_time) / depart_time
		var eased := u * u * (3.0 - 2.0 * u)          # smoothstep
		top.global_position = _arc(apex + _apex_drift(e), e["home"], eased, e)
		# Straighten as it settles, so the countdown begins upright.
		_set_tilt(top, apex_tilt * (1.0 - eased))
		return true

	top.global_position = e["home"]
	_set_tilt(top, 0.0)
	return false


## Behind the camera, offset to the side opposite this top's gauge.
func _start_point(e: Dictionary) -> Vector3:
	var basis := camera.global_transform.basis
	var side := -1.0 if e["gauge_right"] else 1.0
	return camera.global_position \
		+ basis.z * start_behind \
		+ basis.x * side * start_lateral


## Close to the lens, offset toward this top's gauge side.
func _apex_point(e: Dictionary) -> Vector3:
	var basis := camera.global_transform.basis
	var side := 1.0 if e["gauge_right"] else -1.0
	return camera.global_position \
		- basis.z * apex_distance \
		+ basis.x * side * apex_lateral \
		+ basis.y * apex_lift


## Slight lateral drift during the hold, continuing the crossing motion.
func _apex_drift(e: Dictionary) -> Vector3:
	var side := 1.0 if e["gauge_right"] else -1.0
	return camera.global_transform.basis.x * side * apex_lateral * 0.5


## Quadratic Bézier from apex to home, bowed outward so the top sweeps rather
## than travelling in a straight line.
func _arc(from: Vector3, to: Vector3, u: float, e: Dictionary) -> Vector3:
	var mid := (from + to) * 0.5
	var side := 1.0 if e["gauge_right"] else -1.0
	var control := mid + camera.global_transform.basis.x * side * arc_bow \
		+ Vector3.UP * arc_bow * 0.4
	var a := from.lerp(control, u)
	var b := control.lerp(to, u)
	return a.lerp(b, u)


## Tilts the pivot toward the camera so the top's face is visible, leaving the
## mesh free to keep spinning inside it.
func _set_tilt(top: Top, amount: float) -> void:
	if amount <= 0.001:
		top.orientation_pivot.basis = Basis()
		return
	var to_cam := (camera.global_position - top.global_position)
	to_cam.y = 0.0
	if to_cam.length() < 0.001:
		return
	var axis := to_cam.normalized().cross(Vector3.UP).normalized()
	top.orientation_pivot.basis = Basis(axis, -amount)
