class_name AlarmPhone
extends Interactable
## The phone on the nightstand in the ending dream. While it rings it plays a
## looping 3D alarm, its screen pulses and the phone buzzes on the wood.
## Interacting turns it off (once) and emits `alarm_turned_off`.
## Expected children (built by tools/scene_builder/build_dream_ending.gd):
##   Body (Node3D, the phone mesh), ScreenLight (OmniLight3D),
##   AlarmAudio3D (ProceduralSound3D), CollisionShape3D.

signal alarm_turned_off

@export var screen_energy := 0.9
@export var pulse_speed := 1.6 ## screen light pulses per second
@export var buzz_strength := 0.004 ## metres the phone jitters while ringing

var ringing := false

@onready var _body: Node3D = $Body
@onready var _light: OmniLight3D = $ScreenLight
@onready var _alarm: AudioStreamPlayer3D = $AlarmAudio3D
@onready var _screen: MeshInstance3D = $Body/Screen

var _rest: Vector3
var _time := 0.0
var _screen_material: StandardMaterial3D


func _ready() -> void:
	super()
	prompt_text = "PROMPT_ALARM_OFF"
	one_shot = true
	enabled = false # nothing to turn off until it rings
	_rest = _body.position
	_screen_material = _screen.material_override as StandardMaterial3D
	_light.light_energy = 0.0


func start_alarm() -> void:
	ringing = true
	enabled = true
	_alarm.play()


func _process(delta: float) -> void:
	if not ringing:
		return
	_time += delta
	var pulse := 0.5 + 0.5 * sin(_time * pulse_speed * TAU)
	_light.light_energy = screen_energy * (0.35 + 0.65 * pulse)
	if _screen_material:
		_screen_material.emission_energy_multiplier = 0.6 + 1.6 * pulse
	# Buzzing against the nightstand in short bursts.
	var buzzing := fmod(_time, 1.1) < 0.55
	_body.position = _rest + (Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * buzz_strength if buzzing else Vector3.ZERO)


func _on_interact(_interactor: Node3D) -> void:
	if not ringing:
		return
	ringing = false
	_alarm.stop()
	_body.position = _rest
	var tap := AudioStreamPlayer3D.new()
	tap.bus = "SFX"
	tap.stream = ProceduralAudio.get_stream(&"phone_tap")
	add_child(tap)
	tap.play()
	# The screen fades out.
	var tween := create_tween().set_parallel()
	tween.tween_property(_light, "light_energy", 0.0, 0.8)
	if _screen_material:
		tween.tween_property(_screen_material, "emission_energy_multiplier", 0.05, 0.8)
	alarm_turned_off.emit()
