class_name AcidPool
extends Area3D
## The rising acid at the bottom of the shaft (Level 3). It climbs at a fixed
## rate, eats anything it reaches, and gives the level its pressure: there is
## no way back down.

signal player_submerged

@export var size := Vector2(18.0, 18.0)
@export var rise_speed := 0.062 ## meters per second
@export var start_height := -2.0
@export var rising := false

var _surface: MeshInstance3D
var _bubbles: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	position.y = start_height

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 4.0, size.y)
	shape.shape = box
	shape.position = Vector3(0, -2.0, 0) # the volume hangs below the surface
	add_child(shape)

	_surface = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	_surface.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.85, 0.2)
	material.emission_enabled = true
	material.emission = Color(0.3, 1.0, 0.25)
	material.emission_energy_multiplier = 1.6
	material.roughness = 0.15
	material.metallic = 0.3
	_surface.material_override = material
	add_child(_surface)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.4, 1.0, 0.3)
	glow.light_energy = 3.0
	glow.omni_range = 18.0
	glow.position = Vector3(0, 1.5, 0)
	add_child(glow)

	_bubbles = AudioStreamPlayer3D.new()
	_bubbles.bus = "SFX"
	_bubbles.stream = ProceduralAudio.get_stream(&"acid")
	_bubbles.unit_size = 12.0
	_bubbles.max_distance = 45.0
	_bubbles.volume_db = -8.0
	add_child(_bubbles)
	_bubbles.play()

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if rising:
		position.y += rise_speed * delta


## Height of the surface right now (the HUD shows how close it is).
func surface_height() -> float:
	return global_position.y


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		player_submerged.emit()
