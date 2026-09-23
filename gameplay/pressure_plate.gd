class_name PressurePlate
extends Area3D
## Floor switch that stays down while something heavy is on it: the player,
## the NPC, or a crate they pushed onto it (Level 4's final dilemma).

signal pressed(by: Node3D)
signal released

const DOWN := 0.045
## Crates (and anything else heavy enough) join this group.
const HEAVY_GROUP := &"heavy"

@export var plate_size := Vector2(1.4, 1.4)
@export var color := Color(1.0, 0.7, 0.2)

var is_pressed := false
## What is holding it down right now (null when nothing is).
var holder: Node3D

var _plate: MeshInstance3D
var _material: StandardMaterial3D
var _bodies: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER | Layers.NPC | Layers.WORLD
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(plate_size.x, 0.5, plate_size.y)
	shape.shape = box
	shape.position = Vector3(0, 0.25, 0)
	add_child(shape)

	_material = StandardMaterial3D.new()
	_material.albedo_color = color * 0.5
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 1.5
	_plate = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(plate_size.x, 0.08, plate_size.y)
	_plate.mesh = mesh
	_plate.material_override = _material
	_plate.position = Vector3(0, 0.05, 0)
	add_child(_plate)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not _counts(body): # walls and floors slide right past
		return
	if not _bodies.has(body):
		_bodies.append(body)
	_refresh()


func _on_body_exited(body: Node3D) -> void:
	_bodies.erase(body)
	_refresh()


## Only a person or something in the "heavy" group can hold the plate down.
func _counts(body: Node3D) -> bool:
	return body is Player or body is NPCController or body.is_in_group(HEAVY_GROUP)


func _refresh() -> void:
	var down := not _bodies.is_empty()
	if down == is_pressed:
		return
	is_pressed = down
	holder = _bodies.back() if down else null
	_plate.position.y = 0.05 - (DOWN if down else 0.0)
	_material.emission_energy_multiplier = 4.0 if down else 1.5
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(&"click")
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
	if down:
		pressed.emit(holder)
	else:
		released.emit()
