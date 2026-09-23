class_name Flashlight
extends SpotLight3D
## Handheld light, toggled with [flashlight] (F). Levels decide whether the
## player has one (`available`). In Level 2 it is safe to use: the Stalker
## is blind, so only the click of the switch makes a (tiny) sound.

@export var available := false:
	set(value):
		available = value
		if not value:
			visible = false

var _click: AudioStreamPlayer3D


func _ready() -> void:
	visible = false
	_click = AudioStreamPlayer3D.new()
	_click.bus = "SFX"
	_click.stream = ProceduralAudio.get_stream(&"click")
	_click.volume_db = -10.0
	add_child(_click)


func _unhandled_input(event: InputEvent) -> void:
	if not available or not event.is_action_pressed(&"flashlight"):
		return
	var player := owner as Player
	if player and player.state == Player.State.DISABLED:
		return
	visible = not visible
	_click.play()
	get_viewport().set_input_as_handled()
