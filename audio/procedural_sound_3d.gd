class_name ProceduralSound3D
extends AudioStreamPlayer3D
## Positional player for a ProceduralAudio sound (hum, alarm, buzzing phone).

@export var sound_id: StringName = &"hum"
@export var play_on_ready := false
## Audio bus: "SFX" for effects, "BGM" for music / ambience.
@export var audio_bus := "SFX"


func _ready() -> void:
	stream = ProceduralAudio.get_stream(sound_id)
	bus = audio_bus
	if play_on_ready:
		play()


func play_sound(id: StringName) -> void:
	stream = ProceduralAudio.get_stream(id)
	play()
