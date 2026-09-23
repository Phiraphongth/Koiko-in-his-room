class_name HideSpot
extends Interactable
## Locker / box the player can hide in (Level 2). Optional children:
## "HidePoint" (Marker3D, where the player is placed; its +Z faces out) and
## "HideCamera" (Camera3D, first-person view through the vents).

func _init() -> void:
	prompt_text = "PROMPT_HIDE"


func _on_interact(interactor: Node3D) -> void:
	var player := interactor as Player
	if player == null:
		return
	var anchor := get_node_or_null(^"HidePoint") as Node3D
	player.enter_hiding(anchor if anchor else self, get_node_or_null(^"HideCamera") as Camera3D)
