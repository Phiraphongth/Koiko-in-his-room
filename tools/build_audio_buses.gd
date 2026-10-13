extends Node
## Offline tool: generates res://default_bus_layout.tres with the three buses
## SettingsManager controls (Master -> BGM, SFX). Run once; re-run only if the
## bus layout changes.
##   godot --headless --path . res://tools/build_audio_buses.tscn

const OUTPUT := "res://default_bus_layout.tres"
const CHILD_BUSES := ["BGM", "SFX"]
## Headroom so an alarm, a scream and a heartbeat at once cannot clip.
## The listening level itself is trimmed by SettingsManager.BUS_HEADROOM_DB,
## because the volume sliders overwrite these bus volumes at startup.
const CEILING_DB := -1.5


func _ready() -> void:
	AudioServer.set_bus_count(1 + CHILD_BUSES.size())
	AudioServer.set_bus_volume_db(0, 0.0) # SettingsManager owns the master level at runtime
	for i in CHILD_BUSES.size():
		var index := i + 1
		AudioServer.set_bus_name(index, CHILD_BUSES[i])
		AudioServer.set_bus_send(index, "Master")
		AudioServer.set_bus_volume_db(index, 0.0)
	for effect in AudioServer.get_bus_effect_count(0):
		AudioServer.remove_bus_effect(0, 0)
	var limiter: AudioEffect = ClassDB.instantiate("AudioEffectHardLimiter") \
		if ClassDB.class_exists("AudioEffectHardLimiter") else AudioEffectLimiter.new()
	limiter.set(&"ceiling_db", CEILING_DB)
	AudioServer.add_bus_effect(0, limiter)
	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, OUTPUT)
	print("build_audio_buses: %s -> %s (buses: %s)" % [OUTPUT, error_string(err),
		", ".join(range(AudioServer.bus_count).map(func(i: int) -> String: return AudioServer.get_bus_name(i)))])
	get_tree().quit()
