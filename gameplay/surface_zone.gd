class_name SurfaceZone
extends Area3D
## Floor area that changes how loud the player's footsteps are
## (water > 1, carpet < 1). Footsteps inside also switch to splash sounds
## when the multiplier is above 1.5.

@export var noise_multiplier := 2.5


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).push_surface_noise(self, noise_multiplier)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).pop_surface_noise(self)
