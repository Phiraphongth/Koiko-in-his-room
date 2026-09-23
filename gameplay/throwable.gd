class_name Throwable
extends RigidBody3D
## A thrown sound decoy.
##  bottle: shatters on the first hard impact — one loud noise.
##  clock:  lands, then rings for `ring_time` seconds, pulsing noise.
## Noise goes through EventBus.noise_emitted like every other sound source.

@export var kind: StringName = &"bottle"
@export var shatter_noise := 16.0
@export var ring_noise := 18.0
@export var ring_time := 10.0
@export var ring_interval := 0.6

var is_ringing := false

var _triggered := false
var _sound: AudioStreamPlayer3D


## Mesh for a throwable / pickup item, shared with ItemPickup.
static func make_visual(item_kind: StringName) -> Node3D:
	var root := Node3D.new()
	match item_kind:
		&"bottle":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.12, 0.3, 0.15, 0.75)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.05
			root.add_child(_part(_cylinder(0.035, 0.035, 0.2), glass, Vector3(0, 0.1, 0)))
			root.add_child(_part(_cylinder(0.012, 0.03, 0.09), glass, Vector3(0, 0.245, 0)))
		&"clock":
			var body := StandardMaterial3D.new()
			body.albedo_color = Color(0.55, 0.08, 0.06)
			body.metallic = 0.5
			body.roughness = 0.4
			var face := StandardMaterial3D.new()
			face.albedo_color = Color(0.9, 0.88, 0.8)
			var drum := _part(_cylinder(0.07, 0.07, 0.05), body, Vector3(0, 0.08, 0))
			drum.rotation_degrees.x = 90.0
			root.add_child(drum)
			var dial := _part(_cylinder(0.06, 0.06, 0.005), face, Vector3(0, 0.08, 0.026))
			dial.rotation_degrees.x = 90.0
			root.add_child(dial)
			for side in [-1.0, 1.0]:
				var bell := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 0.03
				sphere.height = 0.06
				bell.mesh = sphere
				bell.material_override = body
				bell.position = Vector3(0.045 * side, 0.155, 0)
				root.add_child(bell)
		&"keycard":
			var card := StandardMaterial3D.new()
			card.albedo_color = Color(0.85, 0.85, 0.82)
			var stripe := StandardMaterial3D.new()
			stripe.albedo_color = Color(0.2, 1.0, 0.45)
			stripe.emission_enabled = true
			stripe.emission = Color(0.2, 1.0, 0.45)
			stripe.emission_energy_multiplier = 3.0
			var box := BoxMesh.new()
			box.size = Vector3(0.086, 0.004, 0.054)
			root.add_child(_part(box, card, Vector3(0, 0.003, 0)))
			var band := BoxMesh.new()
			band.size = Vector3(0.086, 0.005, 0.012)
			root.add_child(_part(band, stripe, Vector3(0, 0.004, -0.012)))
	return root


static func _part(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	return instance


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.WORLD
	mass = 0.6
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	add_child(make_visual(kind))
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.06
	capsule.height = 0.25
	shape.shape = capsule
	shape.position = Vector3(0, 0.12, 0)
	add_child(shape)
	_sound = AudioStreamPlayer3D.new()
	_sound.bus = "SFX"
	_sound.unit_size = 6.0
	_sound.max_distance = 45.0
	add_child(_sound)
	body_entered.connect(_on_impact.unbind(1))
	# Safety: if it never hits anything (fell out of the world), trigger anyway.
	get_tree().create_timer(6.0).timeout.connect(_on_impact)


## The Stalker found the ringing clock and smashed it.
func silence() -> void:
	is_ringing = false
	_sound.stop()


func _on_impact() -> void:
	if _triggered or not is_inside_tree():
		return
	_triggered = true
	if kind == &"bottle":
		_shatter()
	else:
		_ring()


func _shatter() -> void:
	EventBus.noise_emitted.emit(global_position, shatter_noise, self)
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(&"glass")
	sound.unit_size = 6.0
	sound.max_distance = 45.0
	get_parent().add_child(sound)
	sound.global_position = global_position
	sound.finished.connect(sound.queue_free)
	sound.play()
	queue_free()


func _ring() -> void:
	is_ringing = true
	_sound.stream = ProceduralAudio.get_stream(&"ring")
	_sound.play()
	var elapsed := 0.0
	while is_ringing and elapsed < ring_time and is_inside_tree():
		EventBus.noise_emitted.emit(global_position, ring_noise, self)
		await get_tree().create_timer(ring_interval).timeout
		elapsed += ring_interval
	silence()
