extends Node
## Offline tool: generates res://default_bus_layout.tres with the three buses
## SettingsManager controls (Master -> BGM, SFX). Run once; re-run only if the
## bus layout changes.
##   godot --headless --path . res://tools/build_audio_buses.tscn

const OUTPUT := "res://default_bus_layout.tres"
const CHILD_BUSES := ["BGM", "SFX"]


func _ready() -> void:
	AudioServer.set_bus_count(1 + CHILD_BUSES.size())
	for i in CHILD_BUSES.size():
		var index := i + 1
		AudioServer.set_bus_name(index, CHILD_BUSES[i])
		AudioServer.set_bus_send(index, "Master")
		AudioServer.set_bus_volume_db(index, 0.0)
	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, OUTPUT)
	print("build_audio_buses: %s -> %s (buses: %s)" % [OUTPUT, error_string(err),
		", ".join(range(AudioServer.bus_count).map(func(i: int) -> String: return AudioServer.get_bus_name(i)))])
	get_tree().quit()
