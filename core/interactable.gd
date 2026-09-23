class_name Interactable
extends Area3D
## Base for anything the player can press [interact] on (doors, lockers,
## keycards, valves...). Attach as a child Area3D with a CollisionShape3D.
## Either connect to `interacted` or extend and override `_on_interact()`.

signal interacted(interactor: Node3D)

## Translation key (see localization/ui.csv) or plain text.
@export var prompt_text := "PROMPT_INTERACT"
@export var enabled := true
@export var one_shot := false


func _ready() -> void:
	collision_layer = Layers.INTERACTABLE
	collision_mask = 0
	monitoring = false # detected by the player's raycast, doesn't need to detect anything itself


func can_interact(_interactor: Node3D) -> bool:
	return enabled


func get_prompt() -> String:
	return Localization.t(prompt_text)


func interact(interactor: Node3D) -> void:
	if not can_interact(interactor):
		return
	interacted.emit(interactor)
	_on_interact(interactor)
	if one_shot:
		enabled = false


## Override in subclasses.
func _on_interact(_interactor: Node3D) -> void:
	pass
