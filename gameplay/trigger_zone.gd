class_name TriggerZone
extends Area3D
## Emits `triggered` when the player walks in. Used for scripted events.

signal triggered(body: Node3D)

@export var one_shot := true
@export var enabled := true

var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not enabled or (one_shot and _fired) or not body is Player:
		return
	_fired = true
	triggered.emit(body)
