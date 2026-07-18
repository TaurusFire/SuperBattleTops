extends Label

@export var top: Top

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if top == null:
		return
	text = "RPM: %d" % top.current_rpm
