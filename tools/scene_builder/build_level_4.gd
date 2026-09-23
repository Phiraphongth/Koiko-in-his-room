extends SceneBuilder
## Offline tool: generates scenes/levels/level_4_valve/level_4.tscn
## ("The Pressure Valve", ♣ 9).
##
## Two sealed rooms with a glass wall between them.
##   West (player): the gas diagram, the pressure gauge, the signal console,
##                  a pressure plate and a crate.
##   East (NPC):    the four valves, their own plate and their own crate.
## Neither side can do the other's job, which is the whole level.

const LEVEL_SCRIPT := preload("res://scenes/levels/level_4_valve/level_4.gd")
const NPC_CONTROLLER := preload("res://gameplay/npc_controller.gd")
const PRESSURE_PLATE := preload("res://gameplay/pressure_plate.gd")
const SIGNAL_BUTTON := preload("res://gameplay/signal_button.gd")

const ROOM_DEPTH := 12.0
const ROOM_WIDTH := 9.0
const HEIGHT := 3.6
## command, symbol, label, colour, pressure change (the diagram shows the change).
const CONSOLE_KEYS: Array = [
	[&"valve_1", "♦", "VALVE 1", Color(0.9, 0.2, 0.15), "-3"],
	[&"valve_2", "♣", "VALVE 2", Color(0.2, 0.9, 0.4), "+1"],
	[&"valve_3", "♠", "VALVE 3", Color(0.6, 0.7, 1.0), "-1"],
	[&"valve_4", "♥", "VALVE 4", Color(1.0, 0.4, 0.6), "+2"],
	[&"hold", "◉", "HOLD", Color(1.0, 0.75, 0.2), ""],
	[&"push", "▣", "PUSH", Color(0.8, 0.8, 0.85), ""],
]


func _output_path() -> String:
	return "res://scenes/levels/level_4_valve/level_4.tscn"


func _build() -> void:
	_root.name = "Level4"
	_root.set_script(LEVEL_SCRIPT)
	_root.set("level_id", &"level_4")
	_root.set("time_limit", 540.0)
	_root.set("autostart", false)
	var timeline: Dictionary[int, StringName] = {180: &"gas_leak", 390: &"comms_error"}
	_root.set("timeline_events", timeline)
	_materials()
	_environment(0.03, Color(0.07, 0.08, 0.09))
	_shell()
	_control_room()
	_valve_room()
	_gas()
	_systems()


func _materials() -> void:
	_m.wall = _textured(Color(0.12, 0.13, 0.14), Color(0.3, 0.3, 0.29), 0.012, 111, 0.85, Vector3.ONE * 0.35)
	_m.floor = _textured(Color(0.1, 0.1, 0.11), Color(0.26, 0.26, 0.25), 0.02, 112, 0.7, Vector3.ONE * 0.4)
	_m.metal = _textured(Color(0.11, 0.12, 0.13), Color(0.28, 0.29, 0.3), 0.03, 113, 0.45, Vector3.ONE, {"metallic": 0.7})
	_m.pipe = _flat(Color(0.22, 0.22, 0.21), 0.5, {"metallic": 0.8})
	_m.wood = _textured(Color(0.16, 0.11, 0.06), Color(0.32, 0.22, 0.12), 0.03, 114, 0.85, Vector3(2.0, 1.0, 0.5))
	_m.diagram = _flat(Color(0.05, 0.12, 0.16), 0.6)
	_m.bulb = _emissive(WARM, 6.0)
	_m.red_lamp = _emissive(BLOOD_RED, 6.0)
	_m.screen = _emissive(Color(0.02, 0.05, 0.04), 1.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.7, 0.75, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.4
	_m.glass = glass


func _shell() -> void:
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_root, arch, "Architecture")
	var span := ROOM_WIDTH * 2.0 + 0.6
	_csg(arch, "Shell", Vector3(0, HEIGHT * 0.5, 0), Vector3(span + 3.0, HEIGHT + 2.0, ROOM_DEPTH + 3.0), _m.wall)
	_csg(arch, "West", Vector3(-(ROOM_WIDTH * 0.5 + 0.3), HEIGHT * 0.5, 0), Vector3(ROOM_WIDTH, HEIGHT, ROOM_DEPTH), _m.wall, true)
	_csg(arch, "East", Vector3(ROOM_WIDTH * 0.5 + 0.3, HEIGHT * 0.5, 0), Vector3(ROOM_WIDTH, HEIGHT, ROOM_DEPTH), _m.wall, true)
	_csg(arch, "Floor", Vector3(0, 0, 0), Vector3(span, 0.1, ROOM_DEPTH + 0.2), _m.floor)
	# Exit corridors, one per room.
	_csg(arch, "WestExit", Vector3(-(ROOM_WIDTH + 2.4), 1.35, 0), Vector3(3.2, 2.7, 2.6), _m.metal, true)
	_csg(arch, "EastExit", Vector3(ROOM_WIDTH + 2.4, 1.35, 0), Vector3(3.2, 2.7, 2.6), _m.metal, true)
	# The glass wall: a frame plus a see-through panel (no collision on the glass
	# itself; the frame and a thin invisible wall keep everyone in their room).
	var divider := StaticBody3D.new()
	_add(_root, divider, "GlassWall")
	_box_shape(divider, Vector3(0.3, HEIGHT, ROOM_DEPTH), Vector3.ZERO)
	_box(_root, "GlassPane", Vector3(0.08, HEIGHT - 0.5, ROOM_DEPTH - 0.6), Vector3(0, HEIGHT * 0.5, 0), _m.glass, false)
	for z in [-ROOM_DEPTH * 0.5 + 0.3, 0.0, ROOM_DEPTH * 0.5 - 0.3]:
		_box(_root, "GlassPost", Vector3(0.24, HEIGHT, 0.24), Vector3(0, HEIGHT * 0.5, z), _m.metal, false)

	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = Vector3(-ROOM_WIDTH * 0.5, 0.1, ROOM_DEPTH * 0.5 - 2.0)


# =========================================================================
# West: the player's control room
# =========================================================================

func _control_room() -> void:
	var room := _group(_root, "ControlRoom")
	var x := -ROOM_WIDTH * 0.5 - 0.3

	# Console desk with the six signal keys, facing the glass.
	_box(room, "Desk", Vector3(2.6, 0.9, 0.8), Vector3(-1.9, 0.45, 1.2), _m.metal)
	var console := _group(room, "Console")
	_unique.append(console)
	for i in CONSOLE_KEYS.size():
		var key: Array = CONSOLE_KEYS[i]
		var button := Area3D.new()
		button.set_script(SIGNAL_BUTTON)
		button.set("command", key[0])
		button.set("symbol", key[1])
		button.set("label_text", key[2])
		button.set("symbol_color", key[3])
		_add(console, button, String(key[0]))
		button.position = Vector3(-2.9 + i * 0.4, 0.95, 1.0)

	# The gas diagram: only this room can read what each symbol does.
	_box(room, "DiagramBoard", Vector3(0.08, 2.0, 3.4), Vector3(x - ROOM_WIDTH * 0.5 + 0.15, 1.8, -1.0), _m.diagram, false)
	var diagram_x := x - ROOM_WIDTH * 0.5 + 0.25
	_label(room, "GAS DIAGRAM", Vector3(diagram_x, 2.6, -1.0), Vector3(0, 90, 0), 64, 0.004, Color(0.6, 0.9, 1.0))
	for i in 4:
		var key: Array = CONSOLE_KEYS[i]
		_label(room, "%s  VALVE %d     %s bar" % [key[1], i + 1, key[4]],
			Vector3(diagram_x, 2.15 - i * 0.38, -1.0), Vector3(0, 90, 0), 44, 0.004, key[3])
	_label(room, "KEEP PRESSURE ON TARGET", Vector3(diagram_x, 0.75, -1.0), Vector3(0, 90, 0), 36, 0.004, Color(0.8, 0.8, 0.75))

	# Pressure gauge, visible from both rooms.
	_box(room, "GaugeBody", Vector3(1.6, 1.0, 0.12), Vector3(-2.0, 2.4, -ROOM_DEPTH * 0.5 + 0.4), _m.screen, false)
	var gauge := _label(room, "10", Vector3(-2.0, 2.5, -ROOM_DEPTH * 0.5 + 0.48), Vector3.ZERO, 120, 0.004, Color(0.4, 1.0, 0.5))
	gauge.name = "Gauge"
	_unique.append(gauge)
	var target_label := _label(room, "TARGET  10", Vector3(-2.0, 2.0, -ROOM_DEPTH * 0.5 + 0.48), Vector3.ZERO, 48, 0.004, Color(0.9, 0.85, 0.5))
	target_label.name = "TargetLabel"
	_unique.append(target_label)

	# Pressure plate + the crate that can hold it down.
	var plate := Area3D.new()
	plate.set_script(PRESSURE_PLATE)
	_add(room, plate, "PlayerPlate").position = Vector3(-6.5, 0.02, -3.0)
	_unique.append(plate)
	var crate := _box(room, "PlayerCrate", Vector3(1.0, 1.0, 1.0), Vector3(-6.5, 0.5, 1.5), _m.wood)
	crate.add_to_group(PRESSURE_PLATE.HEAVY_GROUP, true)
	_unique.append(crate)
	var handle := Area3D.new()
	handle.set_script(INTERACTABLE)
	handle.set("prompt_text", "PROMPT_PUSH_CRATE")
	_add(crate, handle, "PlayerCrateHandle")
	_box_shape(handle, Vector3(1.5, 1.4, 1.5), Vector3.ZERO)
	_unique.append(handle)

	_door_out(room, "PlayerDoor", -(ROOM_WIDTH + 0.85), 0.0)
	_trigger(_root, "ExitTrigger", Vector3(-(ROOM_WIDTH + 3.2), 1.0, 0), Vector3(1.2, 2.0, 2.4))
	_omni(room, "RoomLight", Vector3(-4.5, HEIGHT - 0.3, 0), WARM, 2.2, 10.0, false, Light.STEADY)
	_omni(room, "ExitLightW", Vector3(-(ROOM_WIDTH + 3.0), 2.2, 0), Color(0.7, 1.0, 0.8), 1.5, 5.0, false, Light.STEADY)


# =========================================================================
# East: the NPC's valve room
# =========================================================================

func _valve_room() -> void:
	var room := _group(_root, "ValveRoom")
	var valves := _group(room, "Valves")
	_unique.append(valves)
	for i in 4:
		var key: Array = CONSOLE_KEYS[i]
		var stand := _box(room, "ValveStand", Vector3(0.5, 1.1, 0.5), Vector3(3.0 + i * 1.6, 0.55, -3.6), _m.metal)
		var wheel := Node3D.new()
		_add(valves, wheel, String(key[0]))
		wheel.position = Vector3(3.0 + i * 1.6, 1.25, -3.6)
		_mesh(wheel, "Wheel", _cylinder(0.3, 0.09), Vector3.ZERO, _m.pipe, Vector3(90, 0, 0))
		_label(wheel, key[1], Vector3(0, 0.55, 0), Vector3.ZERO, 72, 0.004, key[3])
		_mesh(stand, "Pipe", _cylinder(0.12, 2.2), Vector3(0, 1.4, 0), _m.pipe)

	var plate := Area3D.new()
	plate.set_script(PRESSURE_PLATE)
	_add(room, plate, "AllyPlate").position = Vector3(6.5, 0.02, -3.0)
	_unique.append(plate)
	var crate := _box(room, "AllyCrate", Vector3(1.0, 1.0, 1.0), Vector3(6.5, 0.5, 1.5), _m.wood)
	crate.add_to_group(PRESSURE_PLATE.HEAVY_GROUP, true)
	_unique.append(crate)

	var ally := CharacterBody3D.new()
	ally.set_script(NPC_CONTROLLER)
	ally.set("npc_name", "AI")
	ally.set("tint", Color(0.35, 0.75, 0.9))
	ally.set("fear", 5)
	ally.set("selfishness", 2)
	ally.set("trust", 7)
	_add(_root, ally, "Ally").position = Vector3(5.0, 0.1, 2.5)
	_unique.append(ally)

	_door_out(room, "AllyDoor", ROOM_WIDTH + 0.85, 180.0)
	_omni(room, "RoomLightE", Vector3(4.5, HEIGHT - 0.3, 0), WARM, 2.2, 10.0, false, Light.BROKEN)
	_omni(room, "ExitLightE", Vector3(ROOM_WIDTH + 3.0, 2.2, 0), Color(0.7, 1.0, 0.8), 1.5, 5.0, false, Light.STEADY)
	_label(room, "♣ 9", Vector3(ROOM_WIDTH - 0.4, 2.6, -ROOM_DEPTH * 0.5 + 0.5), Vector3.ZERO, 150, 0.005, Color(0.5, 0.05, 0.05))


func _door_out(parent: Node, node_name: String, x: float, yaw: float) -> void:
	var door := _door(parent, node_name, Vector3(x, 0.02, 0), yaw, Vector3(2.4, 2.6, 0.15), _m.metal, 1,
		{"slide_offset": Vector3(0, 2.7, 0), "open_time": 2.0, "interactive": false,
		"open_sound": &"shutter", "player_can_close": false})
	_unique.append(door)


## Green haze that fills both rooms once the leak starts.
func _gas() -> void:
	var gas := _group(_root, "GasFog")
	_unique.append(gas)
	var fog := FogVolume.new()
	fog.size = Vector3(ROOM_WIDTH * 2.0 + 1.0, HEIGHT, ROOM_DEPTH)
	var material := FogMaterial.new()
	material.density = 0.28
	material.albedo = Color(0.55, 0.85, 0.45)
	material.emission = Color(0.1, 0.25, 0.08)
	fog.material = material
	_add(gas, fog, "Fog").position = Vector3(0, HEIGHT * 0.5, 0)
	for x in [-6.0, 6.0]:
		var leak := _omni(gas, "LeakLight", Vector3(x, 0.6, -ROOM_DEPTH * 0.5 + 1.0), Color(0.5, 1.0, 0.4), 1.2, 6.0, false, Light.BROKEN)
		_mesh(leak, "Vent", _cylinder(0.16, 0.2), Vector3.ZERO, _m.pipe, Vector3(90, 0, 0))


func _systems() -> void:
	_add_core_systems(-12.0)
	var alarm := AudioStreamPlayer.new()
	alarm.set_script(SOUND)
	alarm.set("sound_id", &"alarm")
	alarm.volume_db = -8.0
	_add(_root, alarm, "Alarm")
	_unique.append(alarm)
