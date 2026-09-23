class_name Examinable
extends Interactable
## Shows a message panel (phone screen, note, sign) when interacted with.

signal examined

@export var title := ""
@export_multiline var body := ""


func _on_interact(_interactor: Node3D) -> void:
	EventBus.message_requested.emit(title, body)
	examined.emit()
