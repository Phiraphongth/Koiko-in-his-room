extends SceneBuilder
## Offline tool: generates scenes/levels/level_2_stalker/level_2.tscn.
## A dark warehouse, 30 x 44 m, three zones separated by low walls:
##   Start room (z 9..14) | Container yard + cage (z -6..9) | Flooded bay with a
##   dry catwalk on the east side (z -18..-6) | Terminal: racks, office, control
##   panel and exit shutter (z -30..-18).
## Everything the Stalker must walk around lives under the NavigationRegion3D,
## which is baked when the level starts.

const LEVEL_SCRIPT := preload("res://scenes/levels/level_2_stalker/level_2.gd")
const HIDE_SPOT := preload("res://gameplay/hide_spot.gd")
const ITEM_PICKUP := preload("res://gameplay/item_pickup.gd")
const SURFACE_ZONE := preload("res://gameplay/surface_zone.gd")
const BLIND_STALKER := preload("res://gameplay/blind_stalker.gd")
const SODIUM := Color(1.0, 0.68, 0.38)

var _nav: NavigationRegion3D


func _output_path() -> String:
	return "res://scenes/levels/level_2_stalker/level_2.tscn"


func _build() -> void:
	_root.name = "Level2"
	_root.set_script(LEVEL_SCRIPT)
	_root.set("level_id", &"level_2")
	_root.set("time_limit", 600.0)
	_root.set("autostart", false)
	var timeline: Dictionary[int, StringName] = {300: &"five_minutes", 540: &"one_minute"}
	_root.set("timeline_events", timeline)
	_materials()
	# Dark enough to be frightening, light enough to read the yard: the level
	# used to render at 0.7% average screen brightness with 99% of pixels at
	# pure black, which is not atmosphere, it is a black screen.
	_environment(0.03, Color(0.11, 0.13, 0.18), 0.9, 1.6, 1.0)
	_navigation()
	_architecture()
	_start_room()
	_container_yard()
	_flooded_bay()
	_terminal()
	_lighting()
	_stalker()
	_systems()


func _materials() -> void:
	_m.concrete = _textured(Color(0.12, 0.12, 0.12), Color(0.3, 0.29, 0.27), 0.01, 61, 1.0, Vector3.ONE * 0.35)
	(_m.concrete as StandardMaterial3D).roughness_texture = _noise(0.007, Color(0.1, 0.1, 0.1), Color.WHITE, 62)
	_m.wall = _textured(Color(0.12, 0.13, 0.13), Color(0.27, 0.28, 0.27), 0.02, 63, 0.7, Vector3(3.0, 0.15, 3.0), {"metallic": 0.4})
	_m.block = _textured(Color(0.16, 0.16, 0.15), Color(0.33, 0.32, 0.3), 0.02, 64, 0.95, Vector3.ONE * 0.5)
	_m.metal = _textured(Color(0.1, 0.1, 0.11), Color(0.28, 0.27, 0.26), 0.03, 65, 0.45, Vector3.ONE, {"metallic": 0.7})
	_m.rust = _textured(Color(0.16, 0.07, 0.04), Color(0.35, 0.2, 0.12), 0.04, 66, 0.8, Vector3.ONE, {"metallic": 0.3})
	_m.wood = _textured(Color(0.16, 0.11, 0.06), Color(0.32, 0.22, 0.12), 0.03, 67, 0.85, Vector3(2.0, 1.0, 0.5))
	_m.locker = _textured(Color(0.13, 0.17, 0.16), Color(0.26, 0.3, 0.28), 0.03, 68, 0.5, Vector3.ONE, {"metallic": 0.5})
	_m.vent = _flat(Color(0.0, 0.0, 0.0), 1.0)
	_m.yellow = _flat(Color(0.55, 0.4, 0.05), 0.6)
	_m.pipe = _flat(Color(0.2, 0.2, 0.19), 0.6, {"metallic": 0.7})
	_m.card = _flat(Color(0.9, 0.9, 0.88), 0.45)
	_m.stain = _flat(Color(0.09, 0.015, 0.01), 0.12)
	_m.sodium = _emissive(SODIUM, 6.0)
	_m.red_lamp = _emissive(BLOOD_RED, 6.0)
	_m.screen = _emissive(Color(0.03, 0.02, 0.02), 1.0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.015, 0.022, 0.025)
	water.roughness = 0.04
	water.metallic = 0.4
	water.normal_enabled = true
	water.normal_texture = _noise(0.03, Color.BLACK, Color.WHITE, 69, true)
	water.normal_scale = 0.25
	water.uv1_triplanar = true
	water.uv1_world_triplanar = true
	water.uv1_scale = Vector3.ONE * 0.5
	_m.water = water
	for color_name: String in ["red", "blue", "green", "orange"]:
		var tint: Color = {"red": Color(0.33, 0.09, 0.06), "blue": Color(0.08, 0.16, 0.3),
			"green": Color(0.1, 0.22, 0.13), "orange": Color(0.42, 0.22, 0.06)}[color_name]
		# Corrugated steel: noise stretched vertically reads as ribs.
		_m["container_" + color_name] = _textured(tint * 0.6, tint, 0.05, 70, 0.6, Vector3(6.0, 0.12, 6.0), {"metallic": 0.5})


func _navigation() -> void:
	_nav = NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS # fast at runtime
	mesh.geometry_collision_mask = Layers.WORLD
	_nav.navigation_mesh = mesh
	_add(_root, _nav, "Navigation")
	_unique.append(_nav)


func _architecture() -> void:
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_nav, arch, "Architecture")
	_csg(arch, "Shell", Vector3(0, 4, -11), Vector3(32, 9, 52), _m.wall)
	_csg(arch, "Interior", Vector3(0, 4, -8), Vector3(30, 8, 44), _m.wall, true)
	_csg(arch, "ExitTunnel", Vector3(-1, 1.75, -33.5), Vector3(4, 3.5, 7), _m.metal, true)
	for skylight in [Vector3(-6, 8.25, 4), Vector3(6, 8.25, -12), Vector3(-3, 8.25, -24)]:
		_csg(arch, "Skylight", skylight, Vector3(3, 1.2, 3), _m.wall, true)
	_csg(arch, "Floor", Vector3(0, 0, -8), Vector3(30.1, 0.04, 44.1), _m.concrete)
	_csg(arch, "ExitFloor", Vector3(-1, 0, -33.5), Vector3(4.1, 0.04, 7), _m.metal)
	# Low block walls between zones (open above, gaps to pass through).
	for wall in [[-8.0, 9.0, 14.0], [8.0, 9.0, 14.0],
			[-12.5, -6.0, 5.0], [-0.5, -6.0, 9.0], [10.5, -6.0, 3.0],
			[-12.0, -18.0, 6.0], [0.5, -18.0, 9.0], [11.1, -18.0, 2.2]]:
		_csg(arch, "ZoneWall", Vector3(wall[0], 1.75, wall[1]), Vector3(wall[2], 3.5, 0.3), _m.block)
	# Terminal office (x 8..15, z -27..-21), door gap on its west side.
	_csg(arch, "OfficeWallA", Vector3(8, 1.5, -22), Vector3(0.3, 3, 2), _m.block)
	_csg(arch, "OfficeWallB", Vector3(8, 1.5, -26), Vector3(0.3, 3, 2), _m.block)
	_csg(arch, "OfficeWallN", Vector3(11.5, 1.5, -21), Vector3(7, 3, 0.3), _m.block)
	_csg(arch, "OfficeWallS", Vector3(11.5, 1.5, -27), Vector3(7, 3, 0.3), _m.block)
	_csg(arch, "OfficeRoof", Vector3(11.5, 3.05, -24), Vector3(7.3, 0.1, 6.3), _m.block)


# =========================================================================
# Zones
# =========================================================================

func _start_room() -> void:
	var zone := _group(_nav, "StartRoom")
	_box(zone, "Table", Vector3(1.6, 0.05, 0.8), Vector3(0.4, 0.75, 11.8), _m.wood)
	_box(zone, "TableBase", Vector3(1.4, 0.7, 0.6), Vector3(0.4, 0.37, 11.8), _m.metal)
	_crate(zone, Vector3(-9, 0.6, 12.5), 1.2)
	_crate(zone, Vector3(-7.8, 0.5, 13.2), 1.0)
	_crate(zone, Vector3(9.5, 0.6, 11.0), 1.2)
	_locker(zone, Vector3(-14.68, 0, 11.5), 90.0)
	_pickup(&"bottle", Vector3(0.9, 0.78, 11.8))
	_pickup(&"clock", Vector3(-0.1, 0.78, 11.8))
	_label(zone, "♠", Vector3(-3.0, 2.6, 13.97), Vector3(0, 180, 0), 256, 0.006, Color(0.05, 0.05, 0.05))
	_label(zone, "IT HEARS YOU", Vector3(4.0, 2.2, 13.97), Vector3(0, 180, 0), 96, 0.006, Color(0.45, 0.04, 0.03))
	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = Vector3(0, 0.05, 12.8)


func _container_yard() -> void:
	var zone := _group(_nav, "ContainerYard")
	_container(zone, "ContainerA", Vector3(-9, 1.3, 5.5), false, "red")
	_container(zone, "ContainerA2", Vector3(-9, 3.9, 5.5), false, "blue")
	_container(zone, "ContainerB", Vector3(-2.5, 1.3, 2.5), true, "green")
	_container(zone, "ContainerC", Vector3(5, 1.3, 6), false, "orange")
	_container(zone, "ContainerD", Vector3(11.5, 1.3, 3), true, "blue")
	_container(zone, "ContainerD2", Vector3(11.5, 3.9, 3), true, "red")
	_container(zone, "ContainerE", Vector3(-10, 1.3, -1.5), false, "orange")
	_container(zone, "ContainerF", Vector3(3.5, 1.3, -1), false, "red")
	_open_container(zone, "ContainerG", Vector3(10.5, 0, -3.2), "green")
	_pickup(&"keycard", Vector3(12.6, 0.12, -3.2))
	_crate(zone, Vector3(-5.5, 0.5, 7.6), 1.0)
	_pickup(&"bottle", Vector3(-5.5, 1.0, 7.6))
	_crate(zone, Vector3(6.8, 0.5, 2.4), 1.0)
	_pickup(&"bottle", Vector3(6.8, 1.0, 2.4))
	_crate(zone, Vector3(-13.5, 0.5, 1.0), 1.0)
	_pickup(&"clock", Vector3(-13.5, 1.0, 1.0))
	_crate(zone, Vector3(7.5, 0.45, -4.8), 0.9)
	_locker(zone, Vector3(-14.68, 0, 7.0), 90.0)
	_locker(zone, Vector3(14.68, 0, 0.5), -90.0)
	_locker(zone, Vector3(1.5, 0, -5.55), 0.0)
	_box(zone, "Stain", Vector3(1.4, 0.003, 1.0), Vector3(-4.6, 0.023, -1.2), _m.stain, false, Vector3(0, 30, 0))

	# The cage it is kept in (visual only, so the Stalker can path out).
	var cage := _group(_root, "Cage")
	cage.position = Vector3(-4.5, 0, -3.2)
	for side in [[-1.2, 0.0, 90.0], [1.2, 0.0, 90.0], [0.0, -1.2, 0.0]]:
		_bars(cage, Vector3(side[0], 0, side[1]), side[2], 2.4)
	var door := _group(_root, "CageDoor")
	door.position = Vector3(-5.7, 0, -2.0) # hinge
	_bars(door, Vector3(1.2, 0, 0), 0.0, 2.4)
	_unique.append(door)
	_label(cage, "DO NOT OPEN", Vector3(0, 2.7, 1.25), Vector3.ZERO, 64, 0.004, Color(0.7, 0.55, 0.1))


func _flooded_bay() -> void:
	var zone := _group(_nav, "FloodedBay")
	for pillar in [Vector3(-6, 4, -9), Vector3(6, 4, -9), Vector3(-6, 4, -15), Vector3(6, 4, -15)]:
		_box(zone, "Pillar", Vector3(0.6, 8, 0.6), pillar, _m.block)
	# Forklift in the middle of the water, keycard #2 on its raised forks.
	_box(zone, "ForkliftBody", Vector3(1.3, 1.3, 2.2), Vector3(0, 0.65, -12.0), _m.yellow)
	_box(zone, "ForkliftCab", Vector3(1.2, 0.08, 1.2), Vector3(0, 2.2, -11.6), _m.metal, false)
	for x in [-0.45, 0.45]:
		_box(zone, "Mast", Vector3(0.1, 3.2, 0.1), Vector3(x, 1.6, -13.2), _m.metal, false)
	_box(zone, "Pallet", Vector3(1.2, 0.12, 1.1), Vector3(0, 1.35, -13.8), _m.wood, false)
	_pickup(&"keycard", Vector3(0, 1.42, -13.8))
	_crate(zone, Vector3(-9.5, 0.6, -12.5), 1.2)
	_crate(zone, Vector3(-8.5, 0.5, -13.4), 1.0)
	_crate(zone, Vector3(3.5, 0.6, -16.5), 1.2)
	_crate(zone, Vector3(-11, 0.5, -7.6), 1.0)
	_pickup(&"bottle", Vector3(-11, 1.0, -7.6))
	# Dry catwalk along the east wall: slower route, but silent.
	_box(zone, "Catwalk", Vector3(2.6, 0.45, 11), Vector3(13.7, 0.225, -12), _m.metal)
	_ramp(zone, Vector3(13.7, 0.2, -5.55), 13.3)
	_ramp(zone, Vector3(13.7, 0.2, -18.45), -13.3)
	_crate(zone, Vector3(14.2, 0.95, -9.0), 1.0)
	_pickup(&"bottle", Vector3(14.2, 1.45, -9.0))
	_pickup(&"clock", Vector3(13.4, 0.47, -15.5))
	_locker(zone, Vector3(-14.68, 0, -10), 90.0)
	_locker(zone, Vector3(-14.68, 0, -15.5), 90.0)
	_locker(zone, Vector3(14.68, 0.45, -12.5), -90.0)

	# Water (visual, outside the navmesh) + the loud-footstep zone.
	_mesh(_root, "Water", _plane(Vector2(27.4, 12)), Vector3(-1.3, 0.08, -12), _m.water)
	var splash := Area3D.new()
	splash.set_script(SURFACE_ZONE)
	_add(_root, splash, "WaterZone").position = Vector3(-1.35, 0.5, -12)
	_box_shape(splash, Vector3(27.3, 1.0, 12), Vector3.ZERO)
	_label(_root, "♥10", Vector3(-14.97, 3.0, -12), Vector3(0, 90, 0), 256, 0.006, Color(0.5, 0.03, 0.03))


func _terminal() -> void:
	var zone := _group(_nav, "Terminal")
	for x in [-11.0, -7.0, -3.0]:
		_rack(zone, Vector3(x, 0, -24))
	_crate(zone, Vector3(-13, 0.5, -20), 1.0)
	_pickup(&"bottle", Vector3(-13, 1.0, -20))
	_crate(zone, Vector3(6, 0.5, -21), 1.0)
	_pickup(&"clock", Vector3(6, 1.0, -21))
	_crate(zone, Vector3(6.2, 0.5, -27.4), 1.0)
	_pickup(&"bottle", Vector3(6.2, 1.0, -27.4))
	# Office with keycard #3.
	_box(zone, "Desk", Vector3(1.6, 0.05, 0.8), Vector3(12.5, 0.75, -25.8), _m.wood)
	_box(zone, "DeskBase", Vector3(1.4, 0.7, 0.6), Vector3(12.5, 0.37, -25.8), _m.metal)
	_pickup(&"keycard", Vector3(12.8, 0.78, -25.8))
	_locker(zone, Vector3(14.68, 0, -22.5), -90.0)
	_omni(_root, "OfficeLamp", Vector3(12.5, 2.6, -24.5), SODIUM, 1.6, 7.0, false, Light.BROKEN)
	_locker(zone, Vector3(-14.68, 0, -24), 90.0)
	_locker(zone, Vector3(2.2, 0, -29.68), 0.0)

	# Control panel with three keycard slots.
	_box(zone, "PanelBody", Vector3(1.4, 1.6, 0.4), Vector3(4, 0.8, -29.75), _m.metal)
	_box(_root, "PanelScreen", Vector3(1.0, 0.4, 0.02), Vector3(4, 1.35, -29.54), _m.screen, false)
	_label(_root, "INSERT KEYCARDS", Vector3(4, 1.35, -29.52), Vector3.ZERO, 32, 0.0025, Color(1.0, 0.3, 0.2))
	var slots := _group(_root, "SlotLights")
	_unique.append(slots)
	for i in 3:
		_box(slots, "Slot%d" % i, Vector3(0.12, 0.06, 0.03), Vector3(3.6 + i * 0.4, 1.0, -29.54),
			_emissive(Color(1.0, 0.1, 0.05), 4.0), false)
	var panel := Area3D.new()
	panel.set_script(INTERACTABLE)
	_add(_root, panel, "ControlPanel").position = Vector3(4, 1.0, -29.4)
	_box_shape(panel, Vector3(1.6, 1.4, 0.8), Vector3.ZERO)
	_unique.append(panel)
	var alarm := _sound_3d(_root, "PanelAlarm", &"alarm", Vector3(4, 2.5, -29.5), false)
	alarm.unit_size = 10.0
	alarm.max_distance = 80.0
	_unique.append(alarm)

	# Exit shutter.
	var door := _door(_root, "ExitDoor", Vector3(-1, 0.02, -30.15), 0.0, Vector3(4.1, 3.55, 0.15), _m.metal, 1,
		{"slide_offset": Vector3(0, 3.6, 0), "open_time": 2.6, "interactive": false, "open_sound": &"shutter", "player_can_close": false})
	_unique.append(door)
	_label(_root, "EXIT", Vector3(-1, 3.9, -29.97), Vector3.ZERO, 96, 0.005, Color(0.2, 0.9, 0.4))
	var beacons := _group(_root, "Beacons")
	_unique.append(beacons)
	for x in [-3.4, 1.4]:
		var beacon := _group(beacons, "Beacon")
		beacon.position = Vector3(x, 3.8, -29.8)
		_mesh(beacon, "Lamp", _cylinder(0.08, 0.12), Vector3.ZERO, _m.red_lamp)
		var beam := SpotLight3D.new()
		beam.light_color = BLOOD_RED
		beam.light_energy = 10.0
		beam.spot_range = 14.0
		beam.spot_angle = 18.0
		beam.light_volumetric_fog_energy = 3.0
		_add(beacon, beam, "Beam").rotation_degrees = Vector3(-20, 0, 0)
	_omni(_root, "ExitLight", Vector3(-1, 2.8, -35.5), Color(0.8, 0.9, 1.0), 3.0, 8.0, false, Light.STEADY)
	_trigger(_root, "ExitTrigger", Vector3(-1, 1, -34.2), Vector3(4, 2, 1))


func _lighting() -> void:
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.5, 0.6, 0.85)
	moon.light_energy = 3.6
	moon.shadow_enabled = true
	moon.light_volumetric_fog_energy = 2.5
	_add(_root, moon, "Moonlight").rotation_degrees = Vector3(-62, 25, 0)

	var house := _group(_root, "HouseLights")
	_unique.append(house)
	for pos in [Vector3(0, 7.5, 11.5), Vector3(-7, 7.5, 3), Vector3(7, 7.5, 3), Vector3(-7, 7.5, -12),
			Vector3(7, 7.5, -12), Vector3(-7, 7.5, -24), Vector3(7, 7.5, -24)]:
		# Range 12 from 7.5 m up barely reached the floor; 20 actually lights it.
		var lamp := _spot(house, "SodiumLamp", pos, Vector3(-90, 0, 0), SODIUM, 8.0, 20.0, 60.0, false, Light.STEADY, false)
		_mesh(lamp, "Bulb", _cylinder(0.25, 0.12), Vector3(0, 0, 0.1), _m.sodium, Vector3(90, 0, 0))
		lamp.set("emissive_mesh", NodePath("Bulb"))
		lamp.set("emission_energy", 6.0)

	for pos in [Vector3(-14.5, 3, 0), Vector3(14.5, 3, -10), Vector3(-14.5, 3, -20), Vector3(0, 3.3, 8.7)]:
		var red := _omni(_root, "EmergencyLight", pos, BLOOD_RED, 1.6, 15.0, false, Light.STEADY)
		_box(red, "LampMesh", Vector3(0.12, 0.08, 0.12), Vector3.ZERO, _m.red_lamp, false)
		red.set("emissive_mesh", NodePath("LampMesh"))


func _stalker() -> void:
	var stalker := CharacterBody3D.new()
	stalker.set_script(BLIND_STALKER)
	_add(_root, stalker, "Stalker").position = Vector3(-4.5, 0.05, -3.4)
	_unique.append(stalker)
	var patrol := _group(_root, "PatrolPoints")
	_unique.append(patrol)
	for p in [Vector3(-8, 0, 7.5), Vector3(0, 0, 3.5), Vector3(7, 0, 1), Vector3(-12, 0, -4), Vector3(2, 0, -4.5),
			Vector3(-3, 0, 11.5), Vector3(-10, 0, -9), Vector3(4, 0, -9), Vector3(-4, 0, -15), Vector3(9, 0, -15),
			Vector3(-12, 0, -21), Vector3(-5, 0, -26), Vector3(2, 0, -22), Vector3(4, 0, -27.5), Vector3(11, 0, -24)]:
		var marker := Marker3D.new()
		_add(patrol, marker, "Point").position = p


func _systems() -> void:
	_add_core_systems(-12.0)
	_root.get_node(^"HUD").set("show_heart_monitor", true)


# =========================================================================
# Props
# =========================================================================

func _container(parent: Node, node_name: String, center: Vector3, along_z: bool, color: String) -> void:
	var size := Vector3(2.44, 2.6, 6.0) if along_z else Vector3(6.0, 2.6, 2.44)
	_box(parent, node_name, size, center, _m["container_" + color])


## Open at its -x end so the player can walk in.
func _open_container(parent: Node, node_name: String, floor_center: Vector3, color: String) -> void:
	var group := _group(parent, node_name)
	group.position = floor_center
	var material: Material = _m["container_" + color]
	_box(group, "Roof", Vector3(6.0, 0.08, 2.44), Vector3(0, 2.56, 0), material)
	_box(group, "SideA", Vector3(6.0, 2.6, 0.08), Vector3(0, 1.3, 1.18), material)
	_box(group, "SideB", Vector3(6.0, 2.6, 0.08), Vector3(0, 1.3, -1.18), material)
	_box(group, "Back", Vector3(0.08, 2.6, 2.44), Vector3(2.96, 1.3, 0), material)
	_box(group, "DoorLeft", Vector3(0.05, 2.5, 1.2), Vector3(-3.5, 1.25, 1.7), material, true, Vector3(0, -60, 0))


func _crate(parent: Node, center: Vector3, size: float) -> void:
	_box(parent, "Crate", Vector3.ONE * size, center, _m.wood, true, Vector3(0, _rng.randf_range(-15, 15), 0))


## Locker you can hide in. Its front (+Z) faces away from the wall.
func _locker(parent: Node, pos: Vector3, yaw: float) -> void:
	var locker := _group(parent, "Locker")
	locker.position = pos
	locker.rotation_degrees.y = yaw
	_box(locker, "Body", Vector3(0.9, 2.1, 0.6), Vector3(0, 1.05, 0), _m.locker)
	for i in 4:
		_box(locker, "Vent", Vector3(0.5, 0.02, 0.01), Vector3(0, 1.55 + i * 0.07, 0.305), _m.vent, false)
	var spot := Area3D.new()
	spot.set_script(HIDE_SPOT)
	spot.set("prompt_text", "PROMPT_HIDE_LOCKER")
	_add(locker, spot, "HideSpot").position = Vector3(0, 1.05, 0)
	_box_shape(spot, Vector3(1.1, 2.2, 0.9), Vector3(0, 0, 0.12))
	var point := Marker3D.new()
	_add(spot, point, "HidePoint").position = Vector3(0, -1.05, 0)
	var cam := Camera3D.new()
	cam.fov = 70.0
	_add(spot, cam, "HideCamera").position = Vector3(0, 0.55, 0.18)
	cam.rotation_degrees = Vector3(-5, 180, 0) # Camera3D looks down -Z; the locker faces +Z


func _rack(parent: Node, base: Vector3) -> void:
	var rack := _group(parent, "Rack")
	rack.position = base
	var body := StaticBody3D.new()
	_add(rack, body, "Body")
	_box_shape(body, Vector3(1.0, 3.6, 7.0), Vector3(0, 1.8, 0))
	for y in [0.1, 1.3, 2.5]:
		_box(rack, "Shelf", Vector3(1.0, 0.06, 7.0), Vector3(0, y, 0), _m.metal, false)
	for z in [-3.45, 3.45]:
		for x in [-0.45, 0.45]:
			_box(rack, "Post", Vector3(0.06, 3.6, 0.06), Vector3(x, 1.8, z), _m.rust, false)
	for i in 10:
		var shelf_y: float = [0.13, 1.33, 2.53][i % 3]
		var box_size := _rng.randf_range(0.4, 0.9)
		_box(rack, "Box", Vector3(0.8, box_size, box_size), Vector3(0, shelf_y + box_size * 0.5, _rng.randf_range(-3.0, 3.0)), _m.wood, false)


func _ramp(parent: Node, center: Vector3, angle: float) -> void:
	_box(parent, "Ramp", Vector3(2.6, 0.1, 2.0), center, _m.metal, true, Vector3(angle, 0, 0))


func _bars(parent: Node, center: Vector3, yaw: float, width: float) -> void:
	var group := _group(parent, "Bars")
	group.position = center
	group.rotation_degrees.y = yaw
	var count := int(width / 0.15)
	for i in count + 1:
		_mesh(group, "Bar", _cylinder(0.02, 3.0), Vector3(-width * 0.5 + i * 0.15, 1.5, 0), _m.rust)
	for y in [0.1, 2.95]:
		_mesh(group, "Rail", _cylinder(0.03, width), Vector3(0, y, 0), _m.rust, Vector3(0, 0, 90))


func _pickup(item_id: StringName, pos: Vector3) -> void:
	var pickup := Area3D.new()
	pickup.set_script(ITEM_PICKUP)
	pickup.set("item_id", item_id)
	_add(_root, pickup, "Pickup_" + String(item_id)).position = pos


func _plane(size: Vector2) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = size
	return plane
