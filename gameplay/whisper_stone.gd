class_name WhisperStone
extends Interactable
## One of the three stones hidden in the maze. Each one whispers continuously,
## so the player can find it by ear even when the walls keep changing.

signal collected(stone: WhisperStone)

const GLOW := Color(0.45, 0.85, 1.0)

var _light: OmniLight3D
var _mesh: MeshInstance3D
var _whisper: AudioStreamPlayer3D


func _ready() -> void:
	super()
	prompt_text = "PROMPT_TOUCH_STONE"
	one_shot = true

	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	_mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = GLOW * 0.4
	material.emission_enabled = true
	material.emission = GLOW
	material.emission_energy_multiplier = 2.5
	_mesh.material_override = material
	_mesh.position = Vector3(0, 0.6, 0)
	add_child(_mesh)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.4, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)

	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.light_energy = 1.6
	_light.omni_range = 5.0
	_light.position = Vector3(0, 0.6, 0)
	add_child(_light)

	_whisper = AudioStreamPlayer3D.new()
	_whisper.bus = "SFX"
	_whisper.stream = ProceduralAudio.get_stream(&"whisper")
	_whisper.unit_size = 4.0
	_whisper.max_distance = 22.0
	_whisper.volume_db = -4.0
	_whisper.position = Vector3(0, 0.8, 0)
	add_child(_whisper)
	_whisper.play()

	# Slow breathing pulse so it reads as alive in the dark.
	var pulse := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_light, "light_energy", 0.7, 1.6)
	pulse.tween_property(_light, "light_energy", 1.8, 1.6)


func _on_interact(_interactor: Node3D) -> void:
	_whisper.stop()
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(&"stone")
	sound.unit_size = 6.0
	add_child(sound)
	sound.play()
	create_tween().tween_property(_light, "light_energy", 0.0, 0.8)
	create_tween().tween_property(_mesh, "scale", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_BACK)
	collected.emit(self)
