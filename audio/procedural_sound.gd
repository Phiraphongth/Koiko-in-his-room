class_name ProceduralSound
extends AudioStreamPlayer
## Non-positional player for a ProceduralAudio sound (ambience, UI, PA).

@export var sound_id: StringName = &"drone"
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
