class_name ItemPickup
extends Interactable
## An item lying in the world (bottle, alarm clock, keycard). Builds its own
## visual and interaction shape; goes into the player's ThrowAbility inventory.

const PROMPT_KEYS: Dictionary[StringName, String] = {&"bottle": "PROMPT_TAKE_BOTTLE",
	&"clock": "PROMPT_TAKE_CLOCK", &"keycard": "PROMPT_TAKE_KEYCARD"}

@export var item_id: StringName = &"bottle"
@export var count := 1


func _ready() -> void:
	super()
	prompt_text = PROMPT_KEYS.get(item_id, "PROMPT_INTERACT")
	add_child(Throwable.make_visual(item_id))
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	shape.position = Vector3(0, 0.1, 0)
	add_child(shape)
	if item_id == &"keycard":
		# Keycards glow faintly so they can be found in the dark.
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.2, 1.0, 0.45)
		glow.light_energy = 0.6
		glow.omni_range = 1.4
		glow.position = Vector3(0, 0.15, 0)
		add_child(glow)


func _on_interact(interactor: Node3D) -> void:
	var inventory := interactor.get_node_or_null(^"ThrowAbility") as ThrowAbility
	if inventory == null:
		return
	inventory.add_item(item_id, count)
	EventBus.item_picked.emit(item_id)
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(&"click")
	get_parent().add_child(sound)
	sound.global_position = global_position
	sound.finished.connect(sound.queue_free)
	sound.play()
	queue_free()
