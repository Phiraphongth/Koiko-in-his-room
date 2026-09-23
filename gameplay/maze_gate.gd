class_name MazeGate
extends Node3D
## A wall panel that slides out of the floor to block a corridor, or sinks
## into it to open one. Every gate knows which maze configurations it is
## open in, so Level 1 can reshuffle the whole labyrinth with one call.
##
## Expected child: "Panel" (AnimatableBody3D) holding the mesh and collider.

signal moved(is_open: bool)

## Configuration indices (0..N-1) in which this gate is open.
@export var open_in: PackedInt32Array = PackedInt32Array([0])
@export var travel := 3.2 ## how far the panel sinks when open
@export var move_time := 1.4

var is_open := true

@onready var _panel: Node3D = $Panel

var _closed_position := Vector3.ZERO
var _tween: Tween


func _ready() -> void:
	_closed_position = _panel.position
	if not is_open_in(0):
		_snap_closed()
	else:
		_panel.position = _closed_position + Vector3.DOWN * travel


func is_open_in(configuration: int) -> bool:
	return open_in.has(configuration)


## Slides to the state this configuration asks for.
func apply_configuration(configuration: int, animate: bool = true) -> void:
	var should_open := is_open_in(configuration)
	if should_open == is_open:
		return
	is_open = should_open
	var target := _closed_position + (Vector3.DOWN * travel if should_open else Vector3.ZERO)
	if _tween:
		_tween.kill()
	if not animate:
		_panel.position = target
		moved.emit(is_open)
		return
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_panel, "position", target, move_time)
	_tween.tween_callback(func() -> void: moved.emit(is_open))


func _snap_closed() -> void:
	is_open = false
	_panel.position = _closed_position
