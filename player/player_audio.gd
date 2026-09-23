class_name PlayerAudio
extends AudioStreamPlayer3D
## Player body sounds: footsteps (4 variations, randomized pitch, volume
## matched to how loud the step is for AI) and the out-of-breath gasp.

const STEP_VARIANTS := 4

@export var step_volume_db := -8.0

var _rng := RandomNumberGenerator.new()
var _last_variant := -1
var _gasp_player: AudioStreamPlayer3D


func _ready() -> void:
	_rng.randomize()
	unit_size = 3.0
	bus = "SFX"
	var player := get_parent() as Player
	player.footstep.connect(_on_footstep)
	player.gasped.connect(_on_gasp)
	_gasp_player = AudioStreamPlayer3D.new()
	_gasp_player.bus = "SFX"
	_gasp_player.stream = ProceduralAudio.get_stream(&"gasp")
	_gasp_player.position = Vector3(0.0, 1.7, 0.0)
	add_child(_gasp_player)


func _on_footstep(loudness: float) -> void:
	var variant := _rng.randi_range(0, STEP_VARIANTS - 1)
	if variant == _last_variant:
		variant = (variant + 1) % STEP_VARIANTS
	_last_variant = variant
	var in_water := (get_parent() as Player).surface_noise_multiplier > 1.5
	stream = ProceduralAudio.get_stream(StringName(("splash_%d" if in_water else "step_%d") % (variant % 3 if in_water else variant)))
	pitch_scale = _rng.randf_range(0.9, 1.1)
	# loudness is a hearing radius (1 m crouch .. 14 m run) -> map to dB.
	volume_db = step_volume_db + linear_to_db(clampf(loudness / 8.0, 0.08, 1.6))
	play()


func _on_gasp() -> void:
	_gasp_player.play()
