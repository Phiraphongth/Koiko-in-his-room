extends SceneBuilder
## Offline tool: generates scenes/levels/level_4_valve/level_4.tscn
## ("The Pressure Valve", ♣ 9).
##
## Two rooms joined by one narrow passage, played alone.
##   West (control room): the gas diagram, the pressure gauge, the exit,
##                        a pressure plate and a crate.
##   East (valve room):   the four valves, a repeater display, a second plate
##                        and crate.
## The diagram and the valves are never in sight of each other, which is the
## whole level.

const LEVEL_SCRIPT := preload("res://scenes/levels/level_4_valve/level_4.gd")
const PRESSURE_PLATE := preload("res://gameplay/pressure_plate.gd")

const ROOM_DEPTH := 12.0
const ROOM_WIDTH := 9.0
const HEIGHT := 3.6
## node name, symbol, colour. What each valve does is written onto the diagram
## at runtime (level_4.gd reroutes them every round).
const VALVES: Array = [
	[&"valve_1", "♦", Color(0.9, 0.2, 0.15)],
	[&"valve_2", "♣", Color(0.2, 0.9, 0.4)],
	[&"valve_3", "♠", Color(0.6, 0.7, 1.0)],
	[&"valve_4", "♥", Color(1.0, 0.4, 0.6)],
]
## The one way between the rooms: a gap in the middle of the dividing wall.
const PASSAGE_Z := 0.0
const PASSAGE_WIDTH := 1.4
## The exit: west wall, north of the gas diagram.
## Lighting: Level 4 is a puzzle that needs reading, so it is lit more
## brightly than the other levels.
const ROOM_LIGHT_ENERGY := 3.5
const FILL_LIGHT_ENERGY := 1.6
const AMBIENT := Color(0.24, 0.24, 0.26)
const AMBIENT_ENERGY := 1.0
const EXPOSURE := 1.35
const EXIT_Z := 3.6
const EXIT_WIDTH := 2.0
const EXIT_DEPTH := 1.3 ## how far the lit niche behind the door goes into the wall


func _output_path() -> String:
	return "res://scenes/levels/level_4_valve/level_4.tscn"


func _build() -> void:
	_root.name = "Level4"
	_root.set_script(LEVEL_SCRIPT)
	_root.set("level_id", &"level_4")
	_root.set("time_limit", 300.0)
	_root.set("autostart", false)
	var timeline: Dictionary[int, StringName] = {45: &"gas_leak", 120: &"power_cut"}
	_root.set("timeline_events", timeline)
	_materials()
	_environment(0.03, Color(0.07, 0.08, 0.09))
	_brighten()
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


## Lifts the shared horror environment (scene_builder._environment) for this
## level only: brighter ambient light and exposure.
func _brighten() -> void:
	var env := (_root.get_node("WorldEnvironment") as WorldEnvironment).environment
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_exposure = EXPOSURE


func _shell() -> void:
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_root, arch, "Architecture")
	var span := ROOM_WIDTH * 2.0 + 0.6
	_csg(arch, "Shell", Vector3(0, HEIGHT * 0.5, 0), Vector3(span + 3.0, HEIGHT + 2.0, ROOM_DEPTH + 3.0), _m.wall)
	_csg(arch, "West", Vector3(-(ROOM_WIDTH * 0.5 + 0.3), HEIGHT * 0.5, 0), Vector3(ROOM_WIDTH, HEIGHT, ROOM_DEPTH), _m.wall, true)
	_csg(arch, "East", Vector3(ROOM_WIDTH * 0.5 + 0.3, HEIGHT * 0.5, 0), Vector3(ROOM_WIDTH, HEIGHT, ROOM_DEPTH), _m.wall, true)
	_csg(arch, "Floor", Vector3(0, 0, 0), Vector3(span, 0.1, ROOM_DEPTH + 0.2), _m.floor)
	# The only way out: a doorway in the control room's west wall, north of
	# the gas diagram, opening into a short niche full of light.
	_csg(arch, "WestExit", Vector3(-(ROOM_WIDTH + 0.3 + EXIT_DEPTH * 0.5) + 0.05, 1.35, EXIT_Z),
		Vector3(EXIT_DEPTH + 0.1, 2.6, EXIT_WIDTH), _m.metal, true)
	# The passage through the solid dividing wall: every trip between the
	# diagram and the valves goes through here.
	_csg(arch, "Passage", Vector3(0, 1.25, PASSAGE_Z), Vector3(1.4, 2.5, PASSAGE_WIDTH), _m.metal, true)
	_omni(_root, "PassageLight", Vector3(0, 2.3, PASSAGE_Z), Color(1.0, 0.55, 0.3), 0.8, 3.0, false, Light.FLICKER)

	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = Vector3(-ROOM_WIDTH * 0.5, 0.1, ROOM_DEPTH * 0.5 - 2.0)


# =========================================================================
# West: the control room
# =========================================================================

func _control_room() -> void:
	var room := _group(_root, "ControlRoom")
	var x := -ROOM_WIDTH * 0.5 - 0.3

	# The gas diagram: the only place that says what each valve does.
	_box(room, "DiagramBoard", Vector3(0.08, 2.0, 3.4), Vector3(x - ROOM_WIDTH * 0.5 + 0.15, 1.8, -1.0), _m.diagram, false)
	var diagram_x := x - ROOM_WIDTH * 0.5 + 0.25
	_label(room, "GAS DIAGRAM", Vector3(diagram_x, 2.6, -1.0), Vector3(0, 90, 0), 64, 0.004, Color(0.6, 0.9, 1.0))
	var diagram := _group(room, "Diagram")
	_unique.append(diagram)
	for i in VALVES.size():
		var valve: Array = VALVES[i]
		var row := _label(diagram, "%s  VALVE %d     ?? bar" % [valve[1], i + 1],
			Vector3(diagram_x, 2.15 - i * 0.38, -1.0), Vector3(0, 90, 0), 44, 0.004, valve[2])
		row.name = "Row%d" % i
	_label(room, "KEEP PRESSURE ON TARGET", Vector3(diagram_x, 0.75, -1.0), Vector3(0, 90, 0), 36, 0.004, Color(0.8, 0.8, 0.75))

	# Pressure gauge. Can be read at an angle from the passage.
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
	_add(room, plate, "ControlPlate").position = Vector3(-6.5, 0.02, -3.0)
	_unique.append(plate)
	_crate(room, "ControlCrate", Vector3(-6.5, 0.5, 1.5))

	_exit(room)
	_omni(room, "RoomLight", Vector3(-4.5, HEIGHT - 0.3, 0), WARM, ROOM_LIGHT_ENERGY, 14.0, false, Light.STEADY)
	for z in [-4.0, 4.0]:
		_omni(room, "RoomFill", Vector3(-4.5, HEIGHT - 0.3, z), WARM, FILL_LIGHT_ENERGY, 9.0, false, Light.STEADY)


# =========================================================================
# East: the valve room
# =========================================================================

func _valve_room() -> void:
	var room := _group(_root, "ValveRoom")
	var valves := _group(room, "Valves")
	_unique.append(valves)
	for i in VALVES.size():
		var valve: Array = VALVES[i]
		var stand := _box(room, "ValveStand", Vector3(0.5, 1.1, 0.5), Vector3(3.0 + i * 1.6, 0.55, -3.6), _m.metal)
		var wheel := Node3D.new()
		_add(valves, wheel, String(valve[0]))
		wheel.position = Vector3(3.0 + i * 1.6, 1.25, -3.6)
		_mesh(wheel, "Wheel", _cylinder(0.3, 0.09), Vector3.ZERO, _m.pipe, Vector3(90, 0, 0))
		_label(wheel, valve[1], Vector3(0, 0.55, 0), Vector3.ZERO, 72, 0.004, valve[2]).name = "Symbol"
		var handle := Area3D.new()
		handle.set_script(INTERACTABLE)
		handle.set("prompt_text", "PROMPT_TURN_VALVE")
		_add(wheel, handle, "Handle")
		_box_shape(handle, Vector3(0.9, 0.9, 0.7), Vector3.ZERO)
		_mesh(stand, "Pipe", _cylinder(0.12, 2.2), Vector3(0, 1.4, 0), _m.pipe)

	# Repeater: pressure + target, until the power cut kills it.
	_box(room, "RepeaterBody", Vector3(1.2, 0.8, 0.12), Vector3(5.4, 2.5, -ROOM_DEPTH * 0.5 + 0.4), _m.screen, false)
	var repeater := _label(room, "10", Vector3(5.4, 2.5, -ROOM_DEPTH * 0.5 + 0.48), Vector3.ZERO, 64, 0.004, Color(0.4, 1.0, 0.5))
	repeater.name = "Repeater"
	_unique.append(repeater)

	var plate := Area3D.new()
	plate.set_script(PRESSURE_PLATE)
	_add(room, plate, "ValvePlate").position = Vector3(6.5, 0.02, 4.0)
	_unique.append(plate)
	_crate(room, "ValveCrate", Vector3(6.5, 0.5, 0.5))

	_omni(room, "RoomLightE", Vector3(4.5, HEIGHT - 0.3, 0), WARM, ROOM_LIGHT_ENERGY, 14.0, false, Light.BROKEN)
	for z in [-4.0, 4.0]:
		_omni(room, "RoomFillE", Vector3(4.5, HEIGHT - 0.3, z), WARM, FILL_LIGHT_ENERGY, 9.0, false, Light.STEADY)
	_label(room, "♣ 9", Vector3(ROOM_WIDTH - 0.4, 2.6, -ROOM_DEPTH * 0.5 + 0.5), Vector3.ZERO, 150, 0.005, Color(0.5, 0.05, 0.05))


## A crate the player can shove onto the plate of its room ("<name>Handle").
func _crate(parent: Node, node_name: String, pos: Vector3) -> void:
	var crate := _box(parent, node_name, Vector3(1.0, 1.0, 1.0), pos, _m.wood)
	crate.add_to_group(PRESSURE_PLATE.HEAVY_GROUP, true)
	_unique.append(crate)
	var handle := Area3D.new()
	handle.set_script(INTERACTABLE)
	handle.set("prompt_text", "PROMPT_PUSH_CRATE")
	_add(crate, handle, node_name + "Handle")
	_box_shape(handle, Vector3(1.5, 1.4, 1.5), Vector3.ZERO)
	_unique.append(handle)


## The exit: a shutter in the west wall that slides up into the wall, an
## EXIT sign over it and a niche behind it that floods the room with white
## light once it opens. The level script
## (level_4.gd) wakes all of it up when both plates are held down.
func _exit(room: Node3D) -> void:
	var wall_x := -(ROOM_WIDTH + 0.3)
	var door := _door(room, "ExitDoor", Vector3(wall_x - 0.08, 0.05, EXIT_Z), 90.0,
		Vector3(EXIT_WIDTH + 0.2, 2.65, 0.12), _m.metal, 1,
		{"slide_offset": Vector3(0, 2.75, 0), "open_time": 2.2, "interactive": false,
		"open_sound": &"shutter", "player_can_close": false})
	_unique.append(door)
	# Frame around the doorway.
	var frame := _flat(Color(0.18, 0.2, 0.2), 0.5, {"metallic": 0.6})
	for side in [-1.0, 1.0]:
		_box(room, "ExitFrame", Vector3(0.14, 2.7, 0.12), Vector3(wall_x + 0.02, 1.35, EXIT_Z + side * (EXIT_WIDTH * 0.5 + 0.06)), frame, false)
	_box(room, "ExitLintel", Vector3(0.14, 0.12, EXIT_WIDTH + 0.36), Vector3(wall_x + 0.02, 2.71, EXIT_Z), frame, false)
	# EXIT sign: dark until the door unlocks.
	_box(room, "ExitSignBox", Vector3(0.08, 0.3, 0.8), Vector3(wall_x + 0.04, 3.05, EXIT_Z), _m.screen, false)
	var sign := _label(room, "EXIT", Vector3(wall_x + 0.09, 3.05, EXIT_Z), Vector3(0, 90, 0), 72, 0.004, Color(0.25, 0.08, 0.06))
	sign.name = "ExitSign"
	_unique.append(sign)
	# The light behind the door: a glowing back wall and a strong lamp.
	var glow_material := _emissive(Color(1.0, 0.96, 0.88), 0.0)
	var back := _box(room, "ExitLightPanel", Vector3(0.04, 2.6, EXIT_WIDTH), Vector3(wall_x - EXIT_DEPTH + 0.08, 1.35, EXIT_Z), glow_material, false)
	back.name = "ExitLightPanel"
	_unique.append(back)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.95, 0.85)
	glow.light_energy = 0.0
	glow.omni_range = 11.0
	glow.shadow_enabled = true
	_add(room, glow, "ExitGlow").position = Vector3(wall_x - EXIT_DEPTH * 0.5, 1.5, EXIT_Z)
	_unique.append(glow)
	_trigger(_root, "ExitTrigger", Vector3(wall_x - EXIT_DEPTH * 0.5 - 0.1, 1.0, EXIT_Z), Vector3(EXIT_DEPTH - 0.4, 2.0, EXIT_WIDTH - 0.2))


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
	_add_core_systems(1.0, &"music_level_4")
	var alarm := AudioStreamPlayer.new()
	alarm.set_script(SOUND)
	alarm.set("sound_id", &"alarm")
	alarm.volume_db = -8.0
	_add(_root, alarm, "Alarm")
	_unique.append(alarm)
