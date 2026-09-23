class_name Door
extends Node3D
## Hinged or sliding door.
## Expected children: Panel (AnimatableBody3D; for hinged doors the hinge is
## this node's origin) -> mesh, CollisionShape3D and an Interactable named
## "Interactable". Hinged doors swing away from whoever opens them.

signal opened
signal closed
signal locked_attempt

enum Kind { HINGED, SLIDING }

@export var kind: Kind = Kind.HINGED
@export var locked := false
@export var open_angle_deg := 100.0
@export var slide_offset := Vector3(0.0, 3.0, 0.0)
@export var open_time := 1.4
@export var open_prompt := "PROMPT_OPEN"
@export var close_prompt := "PROMPT_CLOSE"
@export var locked_prompt := "PROMPT_LOCKED"
@export var player_can_close := true
@export var interactive := true ## false = only scripts can open it (gates)
@export var open_sound: StringName = &"creak"

var is_open := false

@onready var _panel: Node3D = $Panel
@onready var _interactable: Interactable = get_node_or_null(^"Panel/Interactable") as Interactable

var _closed_transform: Transform3D
var _tween: Tween
var _sound: AudioStreamPlayer3D


func _ready() -> void:
	_closed_transform = _panel.transform
	_sound = AudioStreamPlayer3D.new()
	_sound.bus = "SFX"
	_sound.unit_size = 4.0
	_sound.position = Vector3(0.5, 1.2, 0.0) if kind == Kind.HINGED else Vector3(0.0, 1.5, 0.0)
	add_child(_sound)
	if _interactable:
		_interactable.interacted.connect(_on_interacted)
	_refresh_prompt()


func open(opener: Node3D = null) -> void:
	if is_open:
		return
	is_open = true
	var target := _closed_transform
	if kind == Kind.HINGED:
		var direction := 1.0
		if opener:
			direction = 1.0 if to_local(opener.global_position).z > 0.0 else -1.0
		target = Transform3D(Basis(Vector3.UP, deg_to_rad(open_angle_deg) * direction), Vector3.ZERO) * _closed_transform
	else:
		target.origin += slide_offset
	_animate(target, open_time, Tween.EASE_OUT)
	_play(open_sound)
	_refresh_prompt()
	opened.emit()


func close(slam: bool = false) -> void:
	if not is_open:
		return
	is_open = false
	_animate(_closed_transform, 0.16 if slam else open_time, Tween.EASE_IN)
	if slam:
		await get_tree().create_timer(0.14).timeout
		_play(&"slam")
	else:
		_play(open_sound)
	_refresh_prompt()
	closed.emit()


func set_locked(value: bool) -> void:
	locked = value
	_refresh_prompt()


## Something on the other side is trying to get through.
func rattle() -> void:
	_play(&"rattle")
	if kind != Kind.HINGED or is_open:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	for i in 10:
		var jitter := Transform3D(Basis(Vector3.UP, deg_to_rad(randf_range(-1.5, 1.5))), Vector3.ZERO)
		_tween.tween_property(_panel, "transform", jitter * _closed_transform, 0.06)
	_tween.tween_property(_panel, "transform", _closed_transform, 0.06)


func _on_interacted(interactor: Node3D) -> void:
	if locked:
		locked_attempt.emit()
		_play(&"rattle", -10.0)
		return
	if is_open:
		if player_can_close:
			close()
	else:
		open(interactor)


func _animate(target: Transform3D, duration: float, ease_type: Tween.EaseType) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_tween.tween_property(_panel, "transform", target, duration)


func _play(id: StringName, volume_db: float = 0.0) -> void:
	_sound.stream = ProceduralAudio.get_stream(id)
	_sound.volume_db = volume_db
	_sound.play()


func _refresh_prompt() -> void:
	if _interactable == null:
		return
	_interactable.enabled = interactive and (not is_open or player_can_close)
	if locked:
		_interactable.prompt_text = locked_prompt
	else:
		_interactable.prompt_text = close_prompt if is_open else open_prompt
