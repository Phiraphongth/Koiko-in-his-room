extends SceneBuilder
## Offline tool: generates scenes/levels/level_1_maze/level_1.tscn
## ("The Maze of Whispers", ♦ ♣).
##
## A 9x9 stone labyrinth carved with depth-first search, then braided (extra
## walls removed) so several routes exist. A dozen of those passages get a
## MazeGate: a panel that rises or sinks depending on the current maze
## configuration, so the layout changes every 35 seconds. Every configuration
## is checked with breadth-first search here, at build time, so the exit can
## always be reached. Laser tripwires cross some corridors, and three whisper
## stones are hidden in far dead ends.

const LEVEL_SCRIPT := preload("res://scenes/levels/level_1_maze/level_1.gd")
const MAZE_GATE := preload("res://gameplay/maze_gate.gd")
const LASER_TRAP := preload("res://gameplay/laser_trap.gd")
const WHISPER_STONE := preload("res://gameplay/whisper_stone.gd")

const CELLS := 9
const CELL := 3.4
const WALL := 0.25
const HEIGHT := 3.2
const CONFIGURATIONS := 3
const GATE_COUNT := 12
const LASER_COUNT := 7
const STONE_COUNT := 3
const START := Vector2i(4, 8)
const EXIT := Vector2i(4, 0)

var _walls: Dictionary[String, bool] = {}          # wall id -> exists
var _gates: Dictionary[String, PackedInt32Array] = {} # wall id -> configurations it is OPEN in
var _distance: Dictionary[Vector2i, int] = {}


func _output_path() -> String:
	return "res://scenes/levels/level_1_maze/level_1.tscn"


func _build() -> void:
	_root.name = "Level1"
	_root.set_script(LEVEL_SCRIPT)
	_root.set("level_id", &"level_1")
	_root.set("time_limit", 360.0)
	_root.set("autostart", false)
	_materials()
	_environment(0.045, Color(0.13, 0.13, 0.17))
	_generate_maze()
	_place_gates()
	_build_shell()
	_build_walls()
	_build_props()
	_systems()


func _materials() -> void:
	_m.stone = _textured(Color(0.10, 0.10, 0.11), Color(0.28, 0.27, 0.26), 0.012, 91, 0.95, Vector3.ONE * 0.35)
	_m.floor = _textured(Color(0.07, 0.07, 0.08), Color(0.22, 0.21, 0.2), 0.02, 92, 0.9, Vector3.ONE * 0.4)
	(_m.floor as StandardMaterial3D).roughness_texture = _noise(0.008, Color(0.15, 0.15, 0.15), Color.WHITE, 93)
	_m.gate = _textured(Color(0.12, 0.09, 0.09), Color(0.3, 0.22, 0.2), 0.03, 94, 0.6, Vector3.ONE, {"metallic": 0.5})
	_m.metal = _textured(Color(0.1, 0.1, 0.11), Color(0.28, 0.27, 0.26), 0.03, 95, 0.45, Vector3.ONE, {"metallic": 0.7})
	_m.card = _flat(Color(0.9, 0.9, 0.88), 0.45)
	_m.pipe = _flat(Color(0.2, 0.2, 0.19), 0.6, {"metallic": 0.7})
	_m.bulb = _emissive(WARM, 6.0)
	_m.red_lamp = _emissive(BLOOD_RED, 6.0)
	_m.screen = _emissive(Color(0.03, 0.02, 0.02), 1.0)


# =========================================================================
# Maze generation
# =========================================================================

func _wall_id(vertical: bool, x: int, z: int) -> String:
	return "%s:%d:%d" % ["v" if vertical else "h", x, z]


## Wall between two neighbouring cells (they must share an edge).
func _wall_between(a: Vector2i, b: Vector2i) -> String:
	if a.x != b.x:
		return _wall_id(true, maxi(a.x, b.x), a.y)
	return _wall_id(false, a.x, maxi(a.y, b.y))


func _generate_maze() -> void:
	for x in CELLS + 1:
		for z in CELLS:
			_walls[_wall_id(true, x, z)] = true
	for x in CELLS:
		for z in CELLS + 1:
			_walls[_wall_id(false, x, z)] = true

	# Depth-first carving.
	var visited: Dictionary[Vector2i, bool] = {START: true}
	var stack: Array[Vector2i] = [START]
	while not stack.is_empty():
		var cell: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for neighbour: Vector2i in _neighbours(cell):
			if not visited.has(neighbour):
				options.append(neighbour)
		if options.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
		_walls[_wall_between(cell, next)] = false
		visited[next] = true
		stack.append(next)

	# Braid: knock out extra walls so the maze has loops (and alternative routes
	# when a gate closes).
	var removed := 0
	while removed < 16:
		var cell := Vector2i(_rng.randi_range(0, CELLS - 1), _rng.randi_range(0, CELLS - 1))
		var neighbours := _neighbours(cell)
		var neighbour := neighbours[_rng.randi_range(0, neighbours.size() - 1)] as Vector2i
		var id := _wall_between(cell, neighbour)
		if _walls.get(id, false):
			_walls[id] = false
			removed += 1

	# Way in and way out.
	_walls[_wall_id(false, START.x, START.y + 1)] = false
	_walls[_wall_id(false, EXIT.x, EXIT.y)] = false


func _neighbours(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbour := cell + offset
		if neighbour.x >= 0 and neighbour.x < CELLS and neighbour.y >= 0 and neighbour.y < CELLS:
			result.append(neighbour)
	return result


## Turns open passages into gates, keeping every configuration solvable.
func _place_gates() -> void:
	var candidates: Array[String] = []
	for x in CELLS:
		for z in CELLS:
			for neighbour: Vector2i in _neighbours(Vector2i(x, z)):
				var id := _wall_between(Vector2i(x, z), neighbour)
				if not _walls.get(id, true) and not candidates.has(id):
					candidates.append(id)
	candidates.shuffle()

	for attempt in 80:
		_gates.clear()
		var chosen := candidates.slice(0, GATE_COUNT)
		for i in chosen.size():
			# Each gate is closed in exactly one configuration.
			var closed_in := (i + attempt) % CONFIGURATIONS
			var open_in := PackedInt32Array()
			for configuration in CONFIGURATIONS:
				if configuration != closed_in:
					open_in.append(configuration)
			_gates[chosen[i]] = open_in
		if _all_configurations_solvable():
			print("  gates placed on attempt %d" % (attempt + 1))
			return
		candidates.shuffle()
	push_warning("build_level_1: no gate layout kept every configuration solvable; gates left open")
	_gates.clear()


func _all_configurations_solvable() -> bool:
	for configuration in CONFIGURATIONS:
		var distance := _flood_fill(configuration)
		if not distance.has(EXIT):
			return false
		if configuration == 0:
			_distance = distance
	return true


## Breadth-first distances from the start cell for one configuration.
func _flood_fill(configuration: int) -> Dictionary[Vector2i, int]:
	var distance: Dictionary[Vector2i, int] = {START: 0}
	var queue: Array[Vector2i] = [START]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for neighbour: Vector2i in _neighbours(cell):
			if distance.has(neighbour):
				continue
			var id := _wall_between(cell, neighbour)
			if _walls.get(id, true):
				continue # solid wall
			if _gates.has(id) and not _gates[id].has(configuration):
				continue # this gate is up in this configuration
			distance[neighbour] = distance[cell] + 1
			queue.append(neighbour)
	return distance


# =========================================================================
# Geometry
# =========================================================================

func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - (CELLS - 1) * 0.5) * CELL, 0.0, (cell.y - (CELLS - 1) * 0.5) * CELL)


func _wall_transform(id: String) -> Array: # [center, size]
	var parts := id.split(":")
	var vertical := parts[0] == "v"
	var x := int(parts[1])
	var z := int(parts[2])
	var half := (CELLS - 1) * 0.5
	if vertical:
		return [Vector3((x - half - 0.5) * CELL, HEIGHT * 0.5, (z - half) * CELL),
			Vector3(WALL, HEIGHT, CELL + WALL)]
	return [Vector3((x - half) * CELL, HEIGHT * 0.5, (z - half - 0.5) * CELL),
		Vector3(CELL + WALL, HEIGHT, WALL)]


func _build_shell() -> void:
	var span := CELLS * CELL
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_root, arch, "Architecture")
	_csg(arch, "Floor", Vector3(0, -0.1, 0), Vector3(span + 8.0, 0.2, span + 20.0), _m.floor)
	_csg(arch, "Ceiling", Vector3(0, HEIGHT + 0.1, 0), Vector3(span + 8.0, 0.2, span + 20.0), _m.stone)
	# Entrance corridor (south) and exit corridor (north).
	var entrance := _cell_center(START) + Vector3(0, 0, CELL * 1.6)
	_csg(arch, "EntranceL", entrance + Vector3(-CELL * 0.6, HEIGHT * 0.5, 0), Vector3(WALL, HEIGHT, CELL * 2.2), _m.stone)
	_csg(arch, "EntranceR", entrance + Vector3(CELL * 0.6, HEIGHT * 0.5, 0), Vector3(WALL, HEIGHT, CELL * 2.2), _m.stone)
	_csg(arch, "EntranceBack", entrance + Vector3(0, HEIGHT * 0.5, CELL * 1.1), Vector3(CELL * 1.4, HEIGHT, WALL), _m.stone)
	var exit_center := _cell_center(EXIT) - Vector3(0, 0, CELL * 1.6)
	_csg(arch, "ExitL", exit_center + Vector3(-CELL * 0.6, HEIGHT * 0.5, 0), Vector3(WALL, HEIGHT, CELL * 2.4), _m.stone)
	_csg(arch, "ExitR", exit_center + Vector3(CELL * 0.6, HEIGHT * 0.5, 0), Vector3(WALL, HEIGHT, CELL * 2.4), _m.stone)
	_csg(arch, "ExitBack", exit_center + Vector3(0, HEIGHT * 0.5, -CELL * 1.25), Vector3(CELL * 1.4, HEIGHT, WALL), _m.stone)

	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = entrance + Vector3(0, 0.05, CELL * 0.7)


func _build_walls() -> void:
	var walls := _group(_root, "Walls")
	var gates := _group(_root, "Gates")
	_unique.append(gates)
	for id: String in _walls:
		if not _walls[id]:
			continue
		var placement := _wall_transform(id)
		_box(walls, "Wall", placement[1], placement[0], _m.stone)
	for id: String in _gates:
		var placement := _wall_transform(id)
		var gate := Node3D.new()
		gate.set_script(MAZE_GATE)
		gate.set("open_in", _gates[id])
		gate.set("travel", HEIGHT + 0.2)
		_add(gates, gate, "Gate")
		var panel := AnimatableBody3D.new()
		_add(gate, panel, "Panel")
		panel.position = placement[0]
		_box(panel, "Mesh", placement[1], Vector3.ZERO, _m.gate, false)
		_box_shape(panel, placement[1], Vector3.ZERO)
		# A warning stripe so raised gates read as machinery, not architecture.
		_box(panel, "Stripe", placement[1] * Vector3(1.02, 0.04, 1.02) + Vector3(0.01, 0, 0.01),
			Vector3(0, HEIGHT * 0.38, 0), _m.red_lamp, false)


func _build_props() -> void:
	var span := (CELLS - 1) * 0.5 * CELL
	# Dim ceiling lights spread over the maze.
	var lights := _group(_root, "MazeLights")
	var lamp_index := 0
	for cx in range(0, CELLS, 2):
		for cz in range(0, CELLS, 2):
			lamp_index += 1
			var cell := Vector2i(cx, cz)
			var lamp := _omni(lights, "Lamp", _cell_center(cell) + Vector3(0, HEIGHT - 0.35, 0),
				WARM, 1.7, 8.0, false, Light.BROKEN if lamp_index % 4 == 0 else Light.STEADY)
			_mesh(lamp, "Bulb", _sphere(0.06), Vector3.ZERO, _m.bulb)
			lamp.set("emissive_mesh", NodePath("Bulb"))

	# Whisper stones: the three cells deepest into the maze.
	var ranked: Array[Vector2i] = []
	for cell: Vector2i in _distance:
		ranked.append(cell)
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _distance[a] > _distance[b])
	var stones := _group(_root, "Stones")
	_unique.append(stones)
	var placed: Array[Vector2i] = []
	for cell: Vector2i in ranked:
		if placed.size() >= STONE_COUNT:
			break
		if cell == EXIT or cell == START:
			continue
		var too_close := false
		for other: Vector2i in placed:
			if absi(other.x - cell.x) + absi(other.y - cell.y) < 4:
				too_close = true
		if too_close:
			continue
		placed.append(cell)
		var stone := Area3D.new()
		stone.set_script(WHISPER_STONE)
		_add(stones, stone, "WhisperStone").position = _cell_center(cell)

	# Laser tripwires across open passages, away from the entrance.
	var lasers := _group(_root, "Lasers")
	_unique.append(lasers)
	var open_ids: Array[String] = []
	for id: String in _walls:
		if not _walls[id] and not _gates.has(id):
			open_ids.append(id)
	open_ids.shuffle()
	var count := 0
	for id: String in open_ids:
		if count >= LASER_COUNT:
			break
		var placement := _wall_transform(id)
		var center: Vector3 = placement[0]
		if center.distance_to(_cell_center(START)) < CELL * 2.0:
			continue
		var trap := Node3D.new()
		trap.set_script(LASER_TRAP)
		trap.set("mode", 0 if count % 2 == 0 else 1) # crouch under / timed blink
		trap.set("length", CELL)
		trap.set("phase", _rng.randf_range(0.0, 4.0))
		_add(lasers, trap, "Laser")
		trap.position = Vector3(center.x, 0, center.z)
		if id.begins_with("v"):
			trap.rotation_degrees.y = 90.0
		count += 1

	# Exit door + trigger.
	var exit_center := _cell_center(EXIT) - Vector3(0, 0, CELL * 0.5)
	var door := _door(_root, "ExitDoor", exit_center + Vector3(0, 0.02, 0), 0.0,
		Vector3(CELL * 1.2, HEIGHT - 0.1, 0.18), _m.metal, 1,
		{"slide_offset": Vector3(0, HEIGHT, 0), "open_time": 2.2, "interactive": false,
		"open_sound": &"shutter", "player_can_close": false})
	_unique.append(door)
	_label(_root, "EXIT", exit_center + Vector3(0, HEIGHT - 0.4, -0.2), Vector3(0, 180, 0), 96, 0.004, Color(0.2, 0.9, 0.4))
	_omni(_root, "ExitLight", _cell_center(EXIT) - Vector3(0, -2.4, CELL * 2.4), Color(0.7, 1.0, 0.8), 2.0, 6.0, false, Light.STEADY)
	_trigger(_root, "ExitTrigger", _cell_center(EXIT) - Vector3(0, -1.0, CELL * 2.2), Vector3(CELL, 2.0, 1.0))

	# Entrance dressing: the cards from the hub keep leading the way in.
	for i in 5:
		_card(_root, _cell_center(START) + Vector3(_rng.randf_range(-1.0, 1.0), 0.02, CELL * (1.0 + i * 0.35)), i)
	_label(_root, "♦  ♣", _cell_center(START) + Vector3(0, 2.2, CELL * 2.65), Vector3.ZERO, 180, 0.005, Color(0.5, 0.05, 0.05))


func _systems() -> void:
	_add_core_systems(-12.0)
	var shift := AudioStreamPlayer.new()
	shift.set_script(SOUND)
	shift.set("sound_id", &"shift")
	shift.volume_db = -4.0
	_add(_root, shift, "ShiftSound")
	_unique.append(shift)
	var siren := AudioStreamPlayer.new()
	siren.set_script(SOUND)
	siren.set("sound_id", &"alarm")
	siren.volume_db = -6.0
	_add(_root, siren, "Siren")
	_unique.append(siren)
