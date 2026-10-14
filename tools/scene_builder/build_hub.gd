extends SceneBuilder
## Offline tool: generates scenes/hub/hub.tscn (Scene 0).
##   Kopiko's room  ->  apartment hallway  ->  game-entry lobby  ->  gate
## Architecture is CSG (easy to reshape in the editor); props are simple
## meshes with procedural materials; atmosphere comes from volumetric fog,
## few strong light sources and flickering practicals.
##
## Run: open build_hub.tscn and press F6, or
##   godot --headless --path . res://tools/scene_builder/build_hub.tscn
## Re-running overwrites hub.tscn, so make layout changes here.

const HUB_SCRIPT := preload("res://scenes/hub/hub.gd")


func _output_path() -> String:
	return "res://scenes/hub/hub.tscn"


func _build() -> void:
	_root.name = "Hub"
	_root.set_script(HUB_SCRIPT)
	_root.set("level_id", &"hub")
	_root.set("autostart", false)
	_materials()
	# The prologue is the player's own flat, not a crime scene: lift the floor
	# of the lighting so the room and the corridor read without a torch.
	_environment(0.02, Color(0.16, 0.17, 0.21), 0.8, 1.45, 1.0)
	_architecture()
	_room()
	_hallway()
	_lobby()
	_systems()


# =========================================================================
# Materials
# =========================================================================

func _materials() -> void:
	_m.plaster = _textured(Color(0.26, 0.25, 0.22), Color(0.52, 0.5, 0.45), 0.012, 1, 0.95, Vector3.ONE * 0.4)
	_m.ceiling = _textured(Color(0.16, 0.16, 0.15), Color(0.34, 0.33, 0.31), 0.02, 2, 0.95, Vector3.ONE * 0.4)
	_m.wood = _textured(Color(0.09, 0.055, 0.03), Color(0.25, 0.15, 0.085), 0.03, 3, 0.65, Vector3(3.0, 1.0, 0.3))
	_m.lino = _textured(Color(0.09, 0.11, 0.09), Color(0.21, 0.23, 0.18), 0.012, 4, 0.5, Vector3.ONE * 0.5)
	_m.concrete = _textured(Color(0.12, 0.12, 0.12), Color(0.3, 0.29, 0.27), 0.01, 5, 1.0, Vector3.ONE * 0.35)
	(_m.concrete as StandardMaterial3D).roughness_texture = _noise(0.006, Color(0.08, 0.08, 0.08), Color.WHITE, 55)
	_m.metal = _textured(Color(0.13, 0.14, 0.15), Color(0.3, 0.3, 0.31), 0.03, 6, 0.45, Vector3.ONE, {"metallic": 0.6})
	_m.door = _textured(Color(0.17, 0.13, 0.09), Color(0.3, 0.23, 0.16), 0.02, 7, 0.6, Vector3(1.0, 3.0, 1.0))
	_m.apartment_door = _textured(Color(0.18, 0.2, 0.2), Color(0.32, 0.34, 0.33), 0.03, 8, 0.5, Vector3.ONE, {"metallic": 0.4})
	_m.fabric = _flat(Color(0.16, 0.19, 0.26), 0.95)
	_m.blanket = _flat(Color(0.3, 0.05, 0.05), 0.95)
	_m.pillow = _flat(Color(0.7, 0.67, 0.6), 0.95)
	_m.plastic = _flat(Color(0.02, 0.02, 0.02), 0.35)
	_m.card = _flat(Color(0.9, 0.9, 0.88), 0.45)
	_m.trash = _flat(Color(0.01, 0.01, 0.012), 0.2)
	_m.paper = _flat(Color(0.62, 0.6, 0.52), 0.9)
	_m.stain = _flat(Color(0.09, 0.015, 0.01), 0.12)
	_m.poster = _flat(Color(0.45, 0.1, 0.08), 0.9)
	_m.pipe = _flat(Color(0.2, 0.2, 0.19), 0.6, {"metallic": 0.7})
	_m.tube = _emissive(TUBE_COLOR, 4.0)
	_m.bulb = _emissive(WARM, 6.0)
	_m.red_lamp = _emissive(BLOOD_RED, 6.0)
	_m.screen = _emissive(Color(0.03, 0.035, 0.04), 1.0)
	_m.monitor = _emissive(Color(0.04, 0.07, 0.1), 0.8)
	_m.phone_screen = _emissive(Color(0.55, 0.8, 1.0), 2.5)


# =========================================================================
# Architecture (CSG): one solid block with the spaces carved out.
# Room x[-2.5,2.5] z[-2.25,2.25] h2.8 | Hallway x[0.4,2.6] z[-2.45,-22] h2.7
# Lobby x[-2.5,5.5] z[-22,-30] h4.5 | Gate x[0.3,2.7] | Vestibule z[-30.2,-34]
# =========================================================================

func _architecture() -> void:
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_root, arch, "Architecture")
	_csg(arch, "Shell", Vector3(1.5, 2.3, -16.1), Vector3(9.0, 5.0, 38.0), _m.plaster)

	_csg(arch, "RoomSpace", Vector3(0.0, 1.4, 0.0), Vector3(5.0, 2.8, 4.5), _m.plaster, true)
	_csg(arch, "HallSpace", Vector3(1.5, 1.35, -12.225), Vector3(2.2, 2.7, 19.55), _m.plaster, true)
	_csg(arch, "LobbySpace", Vector3(1.5, 2.25, -26.0), Vector3(8.0, 4.5, 8.0), _m.plaster, true)
	_csg(arch, "VestibuleSpace", Vector3(1.5, 1.5, -32.1), Vector3(2.4, 3.0, 3.8), _m.metal, true)
	_csg(arch, "RoomDoorway", Vector3(1.5, 1.07, -2.35), Vector3(1.0, 2.1, 0.6), _m.plaster, true)
	_csg(arch, "GateOpening", Vector3(1.5, 1.52, -30.1), Vector3(2.4, 3.0, 0.6), _m.metal, true)
	_csg(arch, "Window", Vector3(-2.8, 1.6, 0.0), Vector3(1.2, 1.2, 1.6), _m.plaster, true)

	# Floors / ceilings as slabs so each space gets its own material.
	_csg(arch, "RoomFloor", Vector3(0.0, 0.0, 0.025), Vector3(5.1, 0.04, 4.55), _m.wood)
	_csg(arch, "HallFloor", Vector3(1.5, 0.0, -12.125), Vector3(2.3, 0.04, 19.75), _m.lino)
	_csg(arch, "LobbyFloor", Vector3(1.5, 0.0, -26.0), Vector3(8.1, 0.04, 8.0), _m.concrete)
	_csg(arch, "VestibuleFloor", Vector3(1.5, 0.0, -32.0), Vector3(2.5, 0.04, 4.0), _m.metal)
	_csg(arch, "RoomCeiling", Vector3(0.0, 2.8, 0.0), Vector3(5.1, 0.04, 4.6), _m.ceiling)
	_csg(arch, "HallCeiling", Vector3(1.5, 2.7, -12.225), Vector3(2.3, 0.04, 19.6), _m.ceiling)
	_csg(arch, "LobbyCeiling", Vector3(1.5, 4.5, -26.0), Vector3(8.1, 0.04, 8.1), _m.ceiling)


# =========================================================================
# Kopiko's room
# =========================================================================

func _room() -> void:
	var room := _group(_root, "Room")

	# Bed (back-left corner, head toward +z).
	_box(room, "BedFrame", Vector3(1.05, 0.32, 2.05), Vector3(-1.95, 0.16, 1.15), _m.door)
	_box(room, "Mattress", Vector3(0.95, 0.18, 1.95), Vector3(-1.95, 0.41, 1.15), _m.fabric, false)
	_box(room, "Pillow", Vector3(0.6, 0.12, 0.35), Vector3(-1.95, 0.56, 1.9), _m.pillow, false, Vector3(0, 6, 0))
	_box(room, "Blanket", Vector3(1.0, 0.07, 1.15), Vector3(-1.9, 0.53, 0.55), _m.blanket, false, Vector3(3, -9, 2))

	# Desk, chair, monitor, phone (right wall).
	_box(room, "DeskTop", Vector3(0.7, 0.04, 1.4), Vector3(2.1, 0.75, 0.9), _m.door)
	for leg in [Vector3(1.8, 0.37, 0.25), Vector3(2.4, 0.37, 0.25), Vector3(1.8, 0.37, 1.55), Vector3(2.4, 0.37, 1.55)]:
		_box(room, "DeskLeg", Vector3(0.04, 0.73, 0.04), leg, _m.metal, false)
	_box(room, "Monitor", Vector3(0.05, 0.34, 0.55), Vector3(2.3, 1.0, 0.95), _m.plastic, false)
	_box(room, "MonitorScreen", Vector3(0.01, 0.3, 0.5), Vector3(2.27, 1.0, 0.95), _m.monitor, false)
	_box(room, "Keyboard", Vector3(0.15, 0.02, 0.42), Vector3(2.02, 0.78, 0.95), _m.plastic, false)
	_box(room, "ChairSeat", Vector3(0.45, 0.05, 0.45), Vector3(1.45, 0.47, 1.1), _m.plastic, true, Vector3(0, 25, 0))
	_box(room, "ChairBack", Vector3(0.05, 0.5, 0.45), Vector3(1.24, 0.75, 1.2), _m.plastic, false, Vector3(0, 25, -8))

	var phone := _box(room, "PhoneBody", Vector3(0.075, 0.012, 0.15), Vector3(1.95, 0.776, 0.45), _m.plastic, false, Vector3(0, 20, 0))
	_box(phone, "Screen", Vector3(0.068, 0.002, 0.14), Vector3(0, 0.007, 0), _m.phone_screen, false)
	var examine := Area3D.new()
	examine.set_script(EXAMINABLE)
	examine.set("prompt_text", "PROMPT_CHECK_PHONE")
	examine.set("title", HUB_SCRIPT.PHONE_TITLE)
	examine.set("body", HUB_SCRIPT.PHONE_BODY)
	_add(phone, examine, "Phone")
	_box_shape(examine, Vector3(0.35, 0.2, 0.4), Vector3.ZERO)
	_unique.append(examine)
	var phone_light := OmniLight3D.new()
	phone_light.light_color = Color(0.55, 0.8, 1.0)
	phone_light.light_energy = 0.15
	phone_light.omni_range = 1.6
	_add(room, phone_light, "PhoneLight").position = Vector3(1.95, 0.9, 0.45)
	_unique.append(phone_light)
	var phone_sound := _sound_3d(room, "PhoneSound", &"buzz", Vector3(1.95, 0.8, 0.45), false)
	phone_sound.volume_db = -2.0
	_unique.append(phone_sound)

	# Clutter.
	_box(room, "Shelf", Vector3(1.2, 1.9, 0.35), Vector3(-1.7, 0.95, -2.05), _m.door)
	for i in 5:
		_box(room, "ShelfBox", Vector3(0.3, 0.25, 0.28), Vector3(-2.1 + i * 0.22, 1.35 + (i % 2) * 0.5, -2.05), _m.paper, false, Vector3(0, _rng.randf_range(-10, 10), 0))
	_mesh(room, "TrashBag", _sphere(0.28), Vector3(2.1, 0.22, -1.8), _m.trash, Vector3(0, 0, 10), Vector3(1.0, 0.8, 1.1))
	_mesh(room, "TrashBag2", _sphere(0.22), Vector3(1.7, 0.18, -1.95), _m.trash, Vector3.ZERO, Vector3(1.1, 0.8, 1.0))
	_box(room, "Rug", Vector3(1.6, 0.01, 1.1), Vector3(-0.3, 0.025, 0.2), _m.blanket, false, Vector3(0, 4, 0))
	_box(room, "Clothes", Vector3(0.5, 0.08, 0.4), Vector3(0.4, 0.06, 1.6), _m.fabric, false, Vector3(0, 30, 0))
	for i in 4:
		_mesh(room, "Bottle", _cylinder(0.035, 0.24), Vector3(-0.6 + i * 0.12, 0.14 if i != 2 else 0.05, -1.7 - (i % 2) * 0.1), _m.plastic, Vector3(0, 0, 90 if i == 2 else 0))
	_box(room, "Poster", Vector3(0.01, 0.8, 0.55), Vector3(2.49, 1.7, -0.9), _m.poster, false, Vector3(0, 0, 2))
	_label(room, "♥ K", Vector3(2.47, 1.75, -0.9), Vector3(0, -90, 0), 128, 0.0025, Color(0.95, 0.85, 0.8))
	_mesh(room, "Clock", _cylinder(0.16, 0.04), Vector3(0.0, 2.15, 2.23), _m.paper, Vector3(90, 0, 0))

	# Ceiling bulb (broken: flickers every few seconds).
	_mesh(room, "Cord", _cylinder(0.006, 0.3), Vector3(0.0, 2.63, 0.3), _m.plastic)
	var bulb := _omni(room, "CeilingBulb", Vector3(0.0, 2.42, 0.3), WARM, 2.4, 9.0, true, Light.BROKEN)
	_mesh(bulb, "Glass", _sphere(0.05), Vector3(0.0, 0.03, 0.0), _m.bulb)
	bulb.set("emissive_mesh", NodePath("Glass"))
	bulb.set("emission_energy", 6.0)

	# Window with blinds; red light from outside cuts through them.
	for i in 9:
		_box(room, "BlindSlat", Vector3(0.015, 0.1, 1.56), Vector3(-2.42, 1.06 + i * 0.135, 0.0), _m.paper, false, Vector3(0, 0, 38))
	_box(room, "WindowSill", Vector3(0.25, 0.04, 1.7), Vector3(-2.4, 0.98, 0.0), _m.door, false)
	var outside := SpotLight3D.new()
	outside.light_color = Color(1.0, 0.16, 0.1)
	outside.light_energy = 9.0
	outside.spot_range = 10.0
	outside.spot_angle = 22.0
	outside.shadow_enabled = true
	outside.light_volumetric_fog_energy = 2.5
	_add(room, outside, "RedSkyLight").position = Vector3(-4.8, 2.9, 0.25)
	outside.rotation_degrees = Vector3(-22, -90, 0)

	# Door to the hallway (hinge at x=1.0, swings into the hallway).
	var door := _door(room, "RoomDoor", Vector3(1.02, 0.02, -2.35), 0.0, Vector3(0.96, 2.06, 0.05), _m.door, 0, {})
	_unique.append(door)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	_add(room, cam, "IntroCamera").position = Vector3(-1.95, 0.72, 1.72)
	cam.rotation_degrees = Vector3(88, 0, 0)
	_unique.append(cam)

	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = Vector3(-1.0, 0.05, 0.9)
	spawn.rotation_degrees = Vector3(0, -90, 0)


# =========================================================================
# Hallway
# =========================================================================

func _hallway() -> void:
	var hall := _group(_root, "Hallway")

	# Fluorescent tubes (spot down + emissive tube + some hum).
	var lights := _group(hall, "HallLights")
	_unique.append(lights)
	var tube_z := [-4.0, -7.5, -11.0, -14.5, -18.0, -21.0]
	var tube_mode := [Light.STEADY, Light.FLICKER, Light.STEADY, Light.STEADY, Light.BROKEN, Light.STEADY]
	for i in tube_z.size():
		var spot := _spot(lights, "Tube%d" % i, Vector3(1.5, 2.62, tube_z[i]), Vector3(-90, 0, 0),
			TUBE_COLOR, 6.0, 9.0, 70.0, i == 0 or i == 2, tube_mode[i], i == 1 or i == 4)
		_box(spot, "TubeMesh", Vector3(0.1, 1.2, 0.035), Vector3(0, 0, 0.05), _m.tube, false)
		spot.set("emissive_mesh", NodePath("TubeMesh"))

	# Red emergency lamps (off until the blackout).
	var emergency := _group(_root, "EmergencyLights")
	_unique.append(emergency)
	var lamp_positions := [Vector3(0.45, 2.3, -6.0), Vector3(2.55, 2.3, -13.0), Vector3(0.45, 2.3, -19.5),
		Vector3(-2.45, 3.5, -24.0), Vector3(5.45, 3.5, -28.0)]
	for i in lamp_positions.size():
		var lamp := _omni(emergency, "Emergency%d" % i, lamp_positions[i], BLOOD_RED, 1.6, 7.0, false, Light.OFF)
		_box(lamp, "LampMesh", Vector3(0.12, 0.08, 0.12), Vector3.ZERO, _m.red_lamp, false)
		lamp.set("emissive_mesh", NodePath("LampMesh"))
		lamp.set("emission_energy", 6.0)

	# Apartment doors along both walls (all locked).
	var numbers := ["301", "302", "303", "304", "305", "306", "307", "308"]
	for i in numbers.size():
		var left := i % 2 == 0
		var z := -4.2 - i * 2.2
		var hinge := Vector3(0.43 if left else 2.57, 0.02, z + (0.0 if left else -0.95))
		var props := {"locked": true, "locked_prompt": "Locked."}
		var apartment_door := _door(hall, "Door" + numbers[i], hinge, 90.0 if left else -90.0, Vector3(0.95, 2.05, 0.06), _m.apartment_door, 0, props)
		_label(apartment_door.get_node("Panel"), numbers[i], Vector3(0.475, 1.72, 0.035), Vector3.ZERO, 64, 0.0015, Color(0.8, 0.8, 0.75))
		if numbers[i] == "305":
			apartment_door.name = "RattleDoor"
			_unique.append(apartment_door)

	# Pipes, junk and debris.
	_mesh(hall, "PipeA", _cylinder(0.05, 19.5), Vector3(0.6, 2.55, -12.2), _m.pipe, Vector3(90, 0, 0))
	_mesh(hall, "PipeB", _cylinder(0.03, 19.5), Vector3(0.75, 2.58, -12.2), _m.pipe, Vector3(90, 0, 0))
	_box(hall, "FallenChair", Vector3(0.45, 0.05, 0.45), Vector3(2.2, 0.25, -9.3), _m.plastic, true, Vector3(70, 20, 0))
	_mesh(hall, "HallTrash", _sphere(0.25), Vector3(0.7, 0.2, -16.3), _m.trash, Vector3.ZERO, Vector3(1.0, 0.8, 1.2))
	for i in 6:
		_box(hall, "Newspaper", Vector3(0.4, 0.004, 0.3), Vector3(_rng.randf_range(0.7, 2.3), 0.024, _rng.randf_range(-20.0, -3.5)), _m.paper, false, Vector3(0, _rng.randf_range(0, 180), 0))
	_box(hall, "Stain", Vector3(0.9, 0.003, 0.6), Vector3(1.8, 0.023, -15.6), _m.stain, false, Vector3(0, 30, 0))

	# The trail of playing cards.
	for i in 13:
		var z := -3.3 - i * 1.5
		var x := 1.5 + sin(i * 1.7) * 0.45
		_card(hall, Vector3(x, 0.022, z), i)

	var stalker := Node3D.new()
	stalker.set_script(STALKER)
	_add(hall, stalker, "Stalker").position = Vector3(2.05, 0.02, -19.4)
	_unique.append(stalker)

	_trigger(hall, "HallTrigger", Vector3(1.5, 1.0, -3.9), Vector3(2.2, 2.0, 0.8))
	_trigger(hall, "ScareTrigger", Vector3(1.5, 1.0, -11.5), Vector3(2.2, 2.0, 0.8))


# =========================================================================
# Entry lobby + gate
# =========================================================================

func _lobby() -> void:
	var lobby := _group(_root, "Lobby")

	# Registration table under a single harsh light.
	_box(lobby, "Table", Vector3(2.0, 0.05, 0.9), Vector3(1.5, 0.75, -26.5), _m.metal)
	for leg in [Vector3(0.6, 0.37, -26.1), Vector3(2.4, 0.37, -26.1), Vector3(0.6, 0.37, -26.9), Vector3(2.4, 0.37, -26.9)]:
		_box(lobby, "TableLeg", Vector3(0.05, 0.73, 0.05), leg, _m.metal, false)
	for i in 5:
		var phone := _box(lobby, "EntryPhone%d" % i, Vector3(0.075, 0.012, 0.15), Vector3(0.9 + i * 0.3, 0.782, -26.4), _m.plastic, false)
		_box(phone, "Screen", Vector3(0.068, 0.002, 0.14), Vector3(0, 0.007, 0), _m.phone_screen, false)
		if i == 2:
			var take := Area3D.new()
			take.set_script(INTERACTABLE)
			take.set("prompt_text", "PROMPT_TAKE_PHONE")
			_add(phone, take, "RegisterPhone")
			_box_shape(take, Vector3(0.4, 0.25, 0.4), Vector3.ZERO)
			_unique.append(take)
	_spot(lobby, "TableLight", Vector3(1.5, 4.4, -26.5), Vector3(-90, 0, 0), Color(1.0, 0.95, 0.85), 16.0, 9.0, 34.0, true, Light.STEADY, false)
	for i in 3:
		var dead := _spot(lobby, "DeadTube%d" % i, Vector3(-0.5 + i * 2.0, 4.45, -23.5), Vector3(-90, 0, 0), TUBE_COLOR, 5.0, 9.0, 65.0, false, Light.FLICKER if i == 2 else Light.STEADY, false)
		_box(dead, "TubeMesh", Vector3(0.1, 1.2, 0.035), Vector3(0, 0, 0.05), _m.tube, false)
		dead.set("emissive_mesh", NodePath("TubeMesh"))

	# Big entry screen on the left wall.
	_box(lobby, "ScreenPanel", Vector3(0.05, 1.8, 3.2), Vector3(-2.47, 2.5, -26.0), _m.screen, false)
	var screen := _label(lobby, "— STANDBY —", Vector3(-2.43, 2.5, -26.0), Vector3(0, 90, 0), 64, 0.004, Color(1.0, 0.3, 0.25))
	screen.name = "EntryScreen"
	_unique.append(screen)
	var screen_glow := OmniLight3D.new()
	screen_glow.light_color = Color(1.0, 0.3, 0.25)
	screen_glow.light_energy = 0.8
	screen_glow.omni_range = 4.0
	_add(lobby, screen_glow, "ScreenGlow").position = Vector3(-2.0, 2.5, -26.0)

	# Card-suit graffiti.
	_label(lobby, "♦", Vector3(5.47, 2.3, -25.5), Vector3(0, -90, 0), 256, 0.006, Color(0.55, 0.02, 0.02))
	_label(lobby, "♣", Vector3(-0.5, 2.6, -22.03), Vector3(0, 180, 0), 256, 0.005, Color(0.08, 0.08, 0.08))
	_label(lobby, "GAME", Vector3(1.5, 3.6, -29.97), Vector3.ZERO, 128, 0.005, Color(0.75, 0.72, 0.68))

	for i in 4:
		_card(lobby, Vector3(1.5 + sin(i * 2.1) * 0.4, 0.022, -22.6 - i * 0.9), 20 + i)
	_box(lobby, "Stain", Vector3(1.2, 0.003, 0.8), Vector3(3.8, 0.023, -28.5), _m.stain, false, Vector3(0, -20, 0))
	_box(lobby, "ToppledChair", Vector3(0.45, 0.05, 0.45), Vector3(4.2, 0.25, -24.0), _m.plastic, true, Vector3(80, -40, 0))

	# Shutter gate + rotating warning beacon.
	var gate := _door(lobby, "Gate", Vector3(1.5, 0.02, -30.15), 0.0, Vector3(2.5, 3.05, 0.12), _m.metal, 1,
		{"slide_offset": Vector3(0, 3.1, 0), "open_time": 2.6, "interactive": false, "open_sound": &"shutter", "player_can_close": false})
	_unique.append(gate)
	var beacon := _group(lobby, "GateBeacon")
	beacon.position = Vector3(1.5, 3.35, -29.85)
	_unique.append(beacon)
	_mesh(beacon, "BeaconLamp", _cylinder(0.08, 0.12), Vector3.ZERO, _m.red_lamp)
	var beam := SpotLight3D.new()
	beam.light_color = BLOOD_RED
	beam.light_energy = 12.0
	beam.spot_range = 12.0
	beam.spot_angle = 18.0
	beam.light_volumetric_fog_energy = 3.0
	_add(beacon, beam, "Beam").rotation_degrees = Vector3(-15, 0, 0)

	var vestibule_light := OmniLight3D.new()
	vestibule_light.light_color = BLOOD_RED
	vestibule_light.light_energy = 1.5
	vestibule_light.omni_range = 5.0
	_add(lobby, vestibule_light, "VestibuleLight").position = Vector3(1.5, 2.6, -33.0)

	_trigger(lobby, "LobbyTrigger", Vector3(1.5, 1.0, -22.8), Vector3(8.0, 2.0, 0.8))
	_trigger(lobby, "GateTrigger", Vector3(1.5, 1.0, -32.2), Vector3(2.4, 2.0, 0.8))


# =========================================================================
# Systems: UI, FX, audio
# =========================================================================

func _systems() -> void:
	_add_core_systems(1.0, &"music_hub")
	var beep := AudioStreamPlayer.new()
	beep.set_script(SOUND)
	beep.set("sound_id", &"beep")
	beep.volume_db = -6.0
	_add(_root, beep, "Beep")
	_unique.append(beep)
	var alarm := _sound_3d(_root, "Alarm", &"alarm", Vector3(1.5, 3.3, -29.6), false)
	alarm.unit_size = 8.0
	alarm.volume_db = -4.0
	_unique.append(alarm)
