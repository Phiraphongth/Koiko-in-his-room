class_name SignalButton
extends Interactable
## One key on the player's signalling console (Level 4). Pressing it sends a
## symbol through the glass to the NPC — that is the only way to talk once
## the comms degrade. The label above it can be hidden when the radio fails,
## leaving only the symbol.

signal sent(command: StringName)

@export var command: StringName = &"valve_1"
@export var symbol := "♦"
@export var label_text := "VALVE 1"
@export var symbol_color := Color(0.9, 0.2, 0.15)

var _symbol_label: Label3D
var _text_label: Label3D
var _light: OmniLight3D


func _ready() -> void:
	super()
	prompt_text = "PROMPT_SEND_SIGNAL"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.4, 0.4)
	shape.shape = box
	add_child(shape)

	var button := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.28, 0.12)
	button.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.1, 0.12)
	material.metallic = 0.5
	button.material_override = material
	add_child(button)

	_symbol_label = _make_label(symbol, 96, Vector3(0, 0, 0.07), symbol_color)
	_text_label = _make_label(label_text, 40, Vector3(0, 0.26, 0.05), Color(0.8, 0.8, 0.75))

	_light = OmniLight3D.new()
	_light.light_color = symbol_color
	_light.light_energy = 0.0
	_light.omni_range = 1.5
	_light.position = Vector3(0, 0, 0.3)
	add_child(_light)


## The 06:30 comms failure: symbols only, no words.
func hide_label() -> void:
	_text_label.visible = false


func _on_interact(_interactor: Node3D) -> void:
	sent.emit(command)
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(&"beep")
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
	var flash := create_tween()
	flash.tween_property(_light, "light_energy", 2.5, 0.05)
	flash.tween_property(_light, "light_energy", 0.0, 0.5)


func _make_label(text: String, size: int, offset: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.0025
	label.modulate = color
	label.outline_size = 6
	label.position = offset
	add_child(label)
	return label
