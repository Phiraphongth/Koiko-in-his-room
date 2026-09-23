extends SceneBuilder
## Offline tool: generates scenes/levels/level_1_warden/level_1.tscn.
## A concrete holding cell: one table under one lamp, the other players
## standing around it, the Warden's screen on the wall, cell bars facing a
## corridor where the Hound prowls, and a sealed exit.
##
## Cell x[-5,5] z[-5,5] h3.2 | Corridor (behind bars) x[-7.2,-5] | Exit x[5,10] z[-1,1]

const LEVEL_SCRIPT := preload("res://scenes/levels/level_1_warden/level_1.gd")
const CARD_UI := preload("res://scenes/levels/level_1_warden/card_ui.gd")


func _output_path() -> String:
	return "res://scenes/levels/level_1_warden/level_1.tscn"


func _build() -> void:
	_root.name = "Level1"
	_root.set_script(LEVEL_SCRIPT)
	_root.set("level_id", &"level_1")
	_materials()
	_environment(0.04, Color(0.04, 0.045, 0.06))
	_architecture()
	_cell()
	_table()
	_corridor()
	_exit()
	_systems()


func _materials() -> void:
	_m.concrete = _textured(Color(0.13, 0.13, 0.13), Color(0.3, 0.29, 0.27), 0.012, 31, 0.95, Vector3.ONE * 0.4)
	_m.wet_floor = _textured(Color(0.07, 0.07, 0.07), Color(0.22, 0.21, 0.2), 0.01, 32, 1.0, Vector3.ONE * 0.4)
	(_m.wet_floor as StandardMaterial3D).roughness_texture = _noise(0.008, Color(0.05, 0.05, 0.05), Color.WHITE, 33)
	_m.ceiling = _textured(Color(0.08, 0.08, 0.08), Color(0.18, 0.18, 0.17), 0.02, 34, 0.95, Vector3.ONE * 0.4)
	_m.metal = _textured(Color(0.1, 0.1, 0.11), Color(0.28, 0.27, 0.26), 0.03, 35, 0.45, Vector3.ONE, {"metallic": 0.7})
	_m.rust = _textured(Color(0.16, 0.07, 0.04), Color(0.35, 0.2, 0.12), 0.04, 36, 0.8, Vector3.ONE, {"metallic": 0.3})
	_m.wood = _textured(Color(0.08, 0.05, 0.03), Color(0.22, 0.14, 0.08), 0.03, 37, 0.6, Vector3(3.0, 1.0, 0.3))
	_m.mattress = _flat(Color(0.32, 0.3, 0.24), 0.95)
	_m.plastic = _flat(Color(0.02, 0.02, 0.02), 0.35)
	_m.pipe = _flat(Color(0.2, 0.2, 0.19), 0.6, {"metallic": 0.7})
	_m.card = _flat(Color(0.9, 0.9, 0.88), 0.45)
	_m.stain = _flat(Color(0.09, 0.015, 0.01), 0.12)
	_m.porcelain = _flat(Color(0.6, 0.6, 0.55), 0.3)
	_m.screen = _emissive(Color(0.03, 0.02, 0.02), 1.0)
	_m.bulb = _emissive(WARM, 8.0)
	_m.red_lamp = _emissive(BLOOD_RED, 6.0)


func _architecture() -> void:
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_root, arch, "Architecture")
	_csg(arch, "Shell", Vector3(1.5, 1.7, 0.0), Vector3(18.5, 3.8, 11.0), _m.concrete)
	_csg(arch, "CellSpace", Vector3(0.0, 1.6, 0.0), Vector3(10.0, 3.2, 10.0), _m.concrete, true)
	_csg(arch, "CorridorSpace", Vector3(-6.1, 1.6, 0.0), Vector3(2.2, 3.2, 10.0), _m.concrete, true)
	_csg(arch, "ExitOpening", Vector3(5.15, 1.22, 0.0), Vector3(0.5, 2.4, 1.6), _m.metal, true)
	_csg(arch, "ExitSpace", Vector3(7.7, 1.3, 0.0), Vector3(4.8, 2.6, 2.0), _m.concrete, true)
	_csg(arch, "CellFloor", Vector3(0.0, 0.0, 0.0), Vector3(10.1, 0.04, 10.1), _m.wet_floor)
	_csg(arch, "CorridorFloor", Vector3(-6.1, 0.0, 0.0), Vector3(2.3, 0.04, 10.1), _m.wet_floor)
	_csg(arch, "ExitFloor", Vector3(7.65, 0.0, 0.0), Vector3(5.0, 0.04, 2.1), _m.metal)
	_csg(arch, "CellCeiling", Vector3(0.0, 3.2, 0.0), Vector3(10.1, 0.04, 10.1), _m.ceiling)


func _cell() -> void:
	var cell := _group(_root, "Cell")
	# Bars between the cell and the corridor (visual) + one collider.
	var bars := _group(cell, "Bars")
	for i in 55:
		_mesh(bars, "Bar", _cylinder(0.022, 3.2), Vector3(-5.0, 1.6, -4.86 + i * 0.18), _m.rust)
	for y in [0.15, 1.1, 3.05]:
		_mesh(bars, "Rail", _cylinder(0.03, 10.0), Vector3(-5.0, y, 0.0), _m.rust, Vector3(90, 0, 0))
	var bar_body := StaticBody3D.new()
	_add(bars, bar_body, "BarCollider")
	_box_shape(bar_body, Vector3(0.1, 3.2, 10.0), Vector3(-5.0, 1.6, 0.0))

	# Bunks, toilet, drain, chains — a place people have been kept for a while.
	_box(cell, "BunkFrame", Vector3(0.9, 0.08, 2.0), Vector3(4.4, 0.45, -3.8), _m.metal)
	_box(cell, "BunkMattress", Vector3(0.85, 0.12, 1.9), Vector3(4.4, 0.55, -3.8), _m.mattress, false)
	_box(cell, "BunkFrameTop", Vector3(0.9, 0.08, 2.0), Vector3(4.4, 1.6, -3.8), _m.metal)
	_box(cell, "BunkMattressTop", Vector3(0.85, 0.12, 1.9), Vector3(4.4, 1.7, -3.8), _m.mattress, false, Vector3(0, 0, 4))
	for post in [Vector3(3.97, 0.9, -4.78), Vector3(4.83, 0.9, -4.78), Vector3(3.97, 0.9, -2.82), Vector3(4.83, 0.9, -2.82)]:
		_box(cell, "BunkPost", Vector3(0.05, 1.8, 0.05), post, _m.metal, false)
	_box(cell, "Toilet", Vector3(0.45, 0.42, 0.6), Vector3(4.6, 0.21, 4.3), _m.porcelain)
	_mesh(cell, "Drain", _cylinder(0.18, 0.01), Vector3(1.8, 0.025, 2.6), _m.metal)
	_box(cell, "Stain", Vector3(1.4, 0.003, 0.9), Vector3(1.6, 0.023, 2.4), _m.stain, false, Vector3(0, 25, 0))
	for i in 3:
		_mesh(cell, "Chain", _cylinder(0.015, 1.1), Vector3(-2.0 + i * 0.35, 2.4, -4.93), _m.rust)
	_mesh(cell, "Bucket", _cylinder(0.16, 0.3), Vector3(-4.3, 0.17, 3.9), _m.rust)

	# Tally marks and card suits scratched into the walls.
	_label(cell, "|||| |||| |||| ||", Vector3(4.97, 1.4, -1.8), Vector3(0, -90, 0), 64, 0.004, Color(0.55, 0.53, 0.5))
	_label(cell, "♣", Vector3(-3.2, 2.2, -4.97), Vector3.ZERO, 256, 0.004, Color(0.05, 0.05, 0.05))
	_label(cell, "DON'T TRUST\nTHE QUIET ONE", Vector3(3.0, 1.5, 4.97), Vector3(0, 180, 0), 64, 0.004, Color(0.45, 0.05, 0.03))

	# Warden's screen.
	_box(cell, "ScreenFrame", Vector3(3.3, 1.9, 0.08), Vector3(0.0, 2.1, -4.95), _m.plastic, false)
	_box(cell, "ScreenPanel", Vector3(3.1, 1.7, 0.02), Vector3(0.0, 2.1, -4.9), _m.screen, false)
	var screen := _label(cell, "♦  ♣\n\nTHE WARDEN'S GAME", Vector3(0.0, 2.1, -4.88), Vector3.ZERO, 72, 0.004, Color(1.0, 0.25, 0.2))
	screen.name = "WardenScreen"
	_unique.append(screen)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.25, 0.2)
	glow.light_energy = 1.2
	glow.omni_range = 5.0
	_add(cell, glow, "ScreenGlow").position = Vector3(0.0, 2.1, -4.3)

	var entry_light := _omni(cell, "EntryLight", Vector3(0.0, 3.0, 3.6), Color(0.7, 0.8, 1.0), 0.8, 5.0, false, Light.BROKEN)
	_mesh(entry_light, "Bulb", _sphere(0.04), Vector3(0.0, 0.1, 0.0), _m.bulb)

	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = Vector3(0.0, 0.05, 4.1)


func _table() -> void:
	var table := _group(_root, "Table")
	_box(table, "TableTop", Vector3(1.9, 0.06, 1.1), Vector3(0.0, 0.78, 0.0), _m.wood)
	for leg in [Vector3(-0.85, 0.38, -0.45), Vector3(0.85, 0.38, -0.45), Vector3(-0.85, 0.38, 0.45), Vector3(0.85, 0.38, 0.45)]:
		_box(table, "TableLeg", Vector3(0.06, 0.76, 0.06), leg, _m.metal, false)
	for i in 7:
		_card(table, Vector3(_rng.randf_range(-0.7, 0.7), 0.815, _rng.randf_range(-0.35, 0.35)), i)

	# The lamp: the room's only real light. Its brightness tracks POWER.
	_mesh(table, "Cord", _cylinder(0.006, 0.6), Vector3(0.0, 2.9, 0.0), _m.plastic)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.06
	shade.bottom_radius = 0.34
	shade.height = 0.26
	_mesh(table, "Shade", shade, Vector3(0.0, 2.5, 0.0), _m.metal)
	var lamp := _spot(table, "TableLamp", Vector3(0.0, 2.4, 0.0), Vector3(-90, 0, 0), WARM, 14.0, 5.5, 55.0, true, Light.STEADY, false)
	_mesh(lamp, "Bulb", _sphere(0.06), Vector3(0.0, 0.0, 0.05), _m.bulb)
	lamp.set("emissive_mesh", NodePath("Bulb"))
	lamp.set("emission_energy", 8.0)
	_unique.append(lamp)

	var seat := Area3D.new()
	seat.set_script(INTERACTABLE)
	seat.set("prompt_text", "Take your place")
	_add(table, seat, "TableSeat").position = Vector3(0.0, 0.9, 0.75)
	_box_shape(seat, Vector3(1.9, 0.7, 0.6), Vector3.ZERO)
	_unique.append(seat)

	var cam := Camera3D.new()
	cam.fov = 58.0
	# Standing at the table, slightly right, so the table sits left of the card UI.
	_add(table, cam, "TableCamera")
	var eye := Vector3(0.75, 2.0, 2.7)
	cam.transform = Transform3D(Basis.looking_at(Vector3(-0.35, 1.05, -0.4) - eye), eye)
	_unique.append(cam)

	# Where the other players stand, all facing the table.
	var spots := _group(_root, "NPCSpots")
	_unique.append(spots)
	var positions := {"Left": Vector3(-1.35, 0.02, 0.05), "BackLeft": Vector3(-0.55, 0.02, -1.1),
		"BackCenter": Vector3(0.0, 0.02, -1.15), "BackRight": Vector3(0.55, 0.02, -1.1), "Right": Vector3(1.35, 0.02, 0.05)}
	for spot_name: String in positions:
		var marker := Marker3D.new()
		_add(spots, marker, spot_name)
		var pos: Vector3 = positions[spot_name]
		marker.position = pos
		marker.rotation.y = atan2(-pos.x, -pos.z) # model front (+Z) toward the table center


func _corridor() -> void:
	var corridor := _group(_root, "Corridor")
	_omni(corridor, "CorridorRedA", Vector3(-6.1, 2.9, -3.0), BLOOD_RED, 1.2, 5.0, false, Light.BROKEN)
	_omni(corridor, "CorridorRedB", Vector3(-6.1, 2.9, 3.0), BLOOD_RED, 0.9, 5.0, false, Light.STEADY)
	var hound := Node3D.new()
	hound.set_script(STALKER)
	hound.set("face_player", false)
	_add(corridor, hound, "Hound").position = Vector3(-6.1, 0.02, -4.5)
	_unique.append(hound)


func _exit() -> void:
	var exit := _group(_root, "Exit")
	var door := _door(exit, "ExitDoor", Vector3(5.12, 0.02, 0.0), 90.0, Vector3(1.7, 2.45, 0.1), _m.metal, 1,
		{"slide_offset": Vector3(1.75, 0, 0), "open_time": 2.4, "interactive": false, "open_sound": &"shutter", "player_can_close": false})
	_unique.append(door)
	_label(exit, "EXIT", Vector3(4.96, 2.7, 0.0), Vector3(0, -90, 0), 96, 0.004, Color(0.7, 0.1, 0.08))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.7)
	light.light_energy = 2.0
	light.omni_range = 5.0
	_add(exit, light, "ExitLight").position = Vector3(8.5, 2.3, 0.0)
	_trigger(exit, "ExitTrigger", Vector3(8.2, 1.0, 0.0), Vector3(1.0, 2.0, 2.0))


func _systems() -> void:
	_add_core_systems(-10.0)
	var cards := CanvasLayer.new()
	cards.set_script(CARD_UI)
	_add(_root, cards, "CardUI")
	_unique.append(cards)
