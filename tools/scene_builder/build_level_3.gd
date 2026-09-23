extends SceneBuilder
## Offline tool: generates scenes/levels/level_3_abyss/level_3.tscn
## ("Vertical Abyss", ♠ 5).
##
## One 18 x 18 m shaft, 44 m tall, climbed in three stages:
##   y 0..9   parkour ledges, vault crates and a wall-run gap
##   y 9..25  neon climbing panels (orange ones break 3 s after you grab them)
##   y 25..36 swing bars across the shaft, ending in a dyno to the roof ledge
## Acid fills the bottom and rises for the whole ten minutes.

const LEVEL_SCRIPT := preload("res://scenes/levels/level_3_abyss/level_3.gd")
const CLIMB_PANEL := preload("res://gameplay/climb_panel.gd")
const SWING_BAR := preload("res://gameplay/swing_bar.gd")
const ACID_POOL := preload("res://gameplay/acid_pool.gd")

const SHAFT := 18.0   # interior width / depth
const TOP := 44.0
const NEON := Color(0.3, 0.9, 1.0)

var _scaffold: Node3D
var _fragile: Node3D


func _output_path() -> String:
	return "res://scenes/levels/level_3_abyss/level_3.tscn"


func _build() -> void:
	_root.name = "Level3"
	_root.set_script(LEVEL_SCRIPT)
	_root.set("level_id", &"level_3")
	_root.set("time_limit", 600.0)
	_root.set("autostart", false)
	var timeline: Dictionary[int, StringName] = {180: &"scaffold_collapse", 420: &"holds_fall"}
	_root.set("timeline_events", timeline)
	_materials()
	_environment(0.02, Color(0.06, 0.09, 0.1))
	_shell()
	_parkour_zone()
	_climbing_zone()
	_swing_zone()
	_roof()
	_hazard()
	_systems()


func _materials() -> void:
	_m.concrete = _textured(Color(0.11, 0.12, 0.12), Color(0.28, 0.29, 0.28), 0.012, 101, 0.95, Vector3.ONE * 0.3)
	_m.steel = _textured(Color(0.1, 0.11, 0.12), Color(0.26, 0.27, 0.29), 0.03, 102, 0.45, Vector3.ONE, {"metallic": 0.7})
	_m.grate = _textured(Color(0.13, 0.13, 0.14), Color(0.3, 0.3, 0.3), 0.08, 103, 0.5, Vector3.ONE * 2.0, {"metallic": 0.6})
	_m.wood = _textured(Color(0.16, 0.11, 0.06), Color(0.32, 0.22, 0.12), 0.03, 104, 0.85, Vector3(2.0, 1.0, 0.5))
	_m.rust = _textured(Color(0.16, 0.07, 0.04), Color(0.35, 0.2, 0.12), 0.04, 105, 0.8, Vector3.ONE, {"metallic": 0.3})
	_m.neon = _emissive(NEON, 4.0)
	_m.bulb = _emissive(WARM, 6.0)
	_m.red_lamp = _emissive(BLOOD_RED, 6.0)


func _shell() -> void:
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_root, arch, "Architecture")
	_csg(arch, "Shell", Vector3(0, TOP * 0.5 - 4.0, 0), Vector3(SHAFT + 4.0, TOP + 8.0, SHAFT + 4.0), _m.concrete)
	_csg(arch, "Interior", Vector3(0, TOP * 0.5 - 4.0, 0), Vector3(SHAFT, TOP + 4.0, SHAFT), _m.concrete, true)
	# Roof corridor out of the shaft (north wall, y 36).
	_csg(arch, "ExitTunnel", Vector3(0, 37.8, -SHAFT * 0.5 - 2.5), Vector3(3.2, 3.2, 6.0), _m.steel, true)
	_csg(arch, "ExitFloor", Vector3(0, 36.1, -SHAFT * 0.5 - 2.5), Vector3(3.3, 0.2, 6.0), _m.grate)

	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = Vector3(0, 1.1, 7.0)


## y 0..9: ledges, crates to vault, and a gap you can only cross by wall-running.
func _parkour_zone() -> void:
	_scaffold = _group(_root, "Scaffold") # everything here drops at 03:00
	_unique.append(_scaffold)
	_platform(_scaffold, Vector3(0, 0.8, 6.5), Vector3(7.0, 0.4, 4.0))
	_platform(_scaffold, Vector3(-4.5, 1.9, 2.0), Vector3(3.4, 0.4, 3.0))
	_platform(_scaffold, Vector3(3.0, 3.0, -0.5), Vector3(3.4, 0.4, 3.0))
	_platform(_scaffold, Vector3(-2.0, 4.2, -4.5), Vector3(3.6, 0.4, 3.0))
	_crates(_scaffold, Vector3(-4.0, 2.5, 0.0))
	_crates(_scaffold, Vector3(2.0, 3.6, -2.5))
	# Wall-run gap: two ledges on the east wall, 5.5 m apart, nothing in between.
	_platform(_scaffold, Vector3(7.4, 5.4, -3.0), Vector3(2.8, 0.4, 2.4))
	_platform(_root, Vector3(7.4, 6.4, 2.5), Vector3(2.8, 0.4, 2.6))
	_label(_root, "WALL RUN →", Vector3(8.85, 7.4, -0.4), Vector3(0, -90, 0), 64, 0.004, NEON)
	_platform(_root, Vector3(2.0, 8.6, 5.5), Vector3(5.0, 0.4, 3.0)) # last ledge before the wall

	for i in 3:
		var lamp := _omni(_root, "ParkourLamp", Vector3(0, 3.0 + i * 3.0, 0), WARM, 1.4, 12.0, false, Light.STEADY)
		_mesh(lamp, "Bulb", _sphere(0.08), Vector3.ZERO, _m.bulb)
		lamp.set("emissive_mesh", NodePath("Bulb"))


## y 9..25: climbing panels on the shaft walls with ledges between them.
func _climbing_zone() -> void:
	var panels := _group(_root, "ClimbPanels")
	_fragile = _group(_root, "FragilePanels") # armed together at 07:00
	_unique.append(_fragile)
	# North wall (faces +Z): the main route.
	_panel(panels, Vector3(-3.0, 9.2, -SHAFT * 0.5 + 0.15), 0.0, false)
	_platform(_root, Vector3(-3.0, 14.4, -7.0), Vector3(3.2, 0.4, 2.6))
	_panel(_fragile, Vector3(2.5, 14.6, -SHAFT * 0.5 + 0.15), 0.0, true)
	_platform(_root, Vector3(2.5, 19.8, -7.0), Vector3(3.2, 0.4, 2.6))
	_panel(panels, Vector3(-3.5, 20.0, -SHAFT * 0.5 + 0.15), 0.0, false)
	_platform(_root, Vector3(-3.5, 25.2, -7.0), Vector3(3.6, 0.4, 2.8))
	# East wall (faces -X): the alternative route, needed once the mains fall.
	_panel(_fragile, Vector3(SHAFT * 0.5 - 0.15, 14.6, 3.0), -90.0, true)
	_platform(_root, Vector3(7.0, 19.8, 3.0), Vector3(2.6, 0.4, 3.2))
	_panel(panels, Vector3(SHAFT * 0.5 - 0.15, 20.0, -1.0), -90.0, false)
	_platform(_root, Vector3(7.0, 25.2, -1.0), Vector3(2.6, 0.4, 3.2))
	_label(_root, "♠ 5", Vector3(0, 21.0, -SHAFT * 0.5 + 0.2), Vector3.ZERO, 200, 0.006, Color(0.5, 0.05, 0.05))


## y 25..36: bars under the ceiling, ending with a dyno to the roof ledge.
func _swing_zone() -> void:
	var bars := _group(_root, "SwingBars")
	_platform(_root, Vector3(-6.0, 25.6, 0.0), Vector3(4.0, 0.4, 4.0)) # launch ledge
	var heights := [29.0, 29.8, 30.6]
	var offsets := [-2.0, 1.6, 5.2]
	for i in 3:
		var bar := Area3D.new()
		bar.set_script(SWING_BAR)
		bar.set("rope_length", 1.6 + i * 0.15)
		_add(bars, bar, "SwingBar").position = Vector3(offsets[i], heights[i], 0.0)
		# Ceiling mount.
		_box(_root, "BarMount", Vector3(0.3, 0.2, 0.3), Vector3(offsets[i], heights[i] + 1.7, 0.0), _m.steel, false)
	_platform(_root, Vector3(8.0, 33.4, 0.0), Vector3(3.0, 0.4, 5.0)) # dyno target
	_label(_root, "DYNO", Vector3(8.8, 34.6, 0.0), Vector3(0, -90, 0), 64, 0.004, NEON)
	for i in 3:
		var lamp := _omni(_root, "SwingLamp", Vector3(0, 27.0 + i * 4.0, 0), NEON, 1.2, 14.0, false, Light.STEADY)
		_mesh(lamp, "Tube", _cylinder(0.06, 1.2), Vector3.ZERO, _m.neon, Vector3(0, 0, 90))
		lamp.set("emissive_mesh", NodePath("Tube"))


func _roof() -> void:
	_platform(_root, Vector3(3.0, 35.8, -4.0), Vector3(6.0, 0.4, 4.0))
	_platform(_root, Vector3(0.0, 36.0, -7.5), Vector3(4.0, 0.4, 3.4))
	var door := _door(_root, "ExitDoor", Vector3(0, 36.22, -SHAFT * 0.5 - 0.1), 0.0,
		Vector3(3.0, 3.0, 0.15), _m.steel, 1,
		{"slide_offset": Vector3(0, 3.1, 0), "open_time": 2.0, "interactive": true,
		"open_prompt": "PROMPT_OPEN", "open_sound": &"shutter", "player_can_close": false})
	_unique.append(door)
	_label(_root, "EXIT", Vector3(0, 39.6, -SHAFT * 0.5 + 0.2), Vector3.ZERO, 96, 0.005, Color(0.2, 0.9, 0.4))
	_omni(_root, "RoofLight", Vector3(0, 38.5, -SHAFT * 0.5 - 4.0), Color(0.8, 0.95, 1.0), 2.5, 8.0, false, Light.STEADY)
	_trigger(_root, "ExitTrigger", Vector3(0, 37.4, -SHAFT * 0.5 - 4.0), Vector3(3.0, 2.4, 1.2))


func _hazard() -> void:
	var acid := Area3D.new()
	acid.set_script(ACID_POOL)
	acid.set("size", Vector2(SHAFT, SHAFT))
	acid.set("start_height", -4.0)
	acid.set("rise_speed", 0.062) # ~37 m over the ten minutes
	_add(_root, acid, "Acid")
	_unique.append(acid)


func _systems() -> void:
	_add_core_systems(-14.0)
	var horn := AudioStreamPlayer.new()
	horn.set_script(SOUND)
	horn.set("sound_id", &"siren_low")
	horn.volume_db = -5.0
	_add(_root, horn, "Horn")
	_unique.append(horn)


# =========================================================================
# Helpers
# =========================================================================

func _platform(parent: Node, center: Vector3, size: Vector3) -> Node3D:
	var platform := _box(parent, "Platform", size, center, _m.grate)
	# Neon edge strip so ledges read in the dark.
	_box(platform, "Edge", Vector3(size.x, 0.05, 0.06), Vector3(0, size.y * 0.5, size.z * 0.5), _m.neon, false)
	return platform


func _crates(parent: Node, base: Vector3) -> void:
	_box(parent, "Crate", Vector3.ONE * 0.9, base, _m.wood, true, Vector3(0, _rng.randf_range(-20, 20), 0))
	_box(parent, "Crate", Vector3.ONE * 0.7, base + Vector3(0.2, 0.8, 0.1), _m.wood, true, Vector3(0, _rng.randf_range(-20, 20), 0))


## A climbing panel flat against a wall; `yaw` 0 faces +Z, -90 faces -X.
func _panel(parent: Node, position: Vector3, yaw: float, breakable: bool) -> void:
	var panel := Area3D.new()
	panel.set_script(CLIMB_PANEL)
	panel.set("breakable", breakable)
	panel.set("size", Vector2(3.0, 5.2))
	_add(parent, panel, "ClimbPanel")
	panel.position = position
	panel.rotation_degrees.y = yaw
