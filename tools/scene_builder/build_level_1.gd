extends SceneBuilder
## Offline tool: generates scenes/levels/level_1_maze/level_1.tscn
## ("The Maze of Whispers", ♦ ♣).
##
## A 9x9 hedge labyrinth in a walled garden, at midday, carved with depth-first search, then braided (extra
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
const LEAF_COVER := preload("res://gameplay/leaf_cover.gd")

const CELLS := 9
const CELL := 3.4
const WALL := 0.25
const HEIGHT := 2.9 ## hedge: over the player's head, under the treeline
const CONFIGURATIONS := 3
const GATE_COUNT := 12
const LASER_COUNT := 7
const STONE_COUNT := 3
const START := Vector2i(4, 8)
const EXIT := Vector2i(4, 0)
const KERB := 0.3 ## stone edging the hedges stand in
const LEAF_SPACING := 0.55 ## distance between leaf clumps on a hedge face
const LEAF_DEPTH := 0.25 ## how far the leaves stand out from a hedge's core

var _walls: Dictionary[String, bool] = {}          # wall id -> exists
var _gates: Dictionary[String, PackedInt32Array] = {} # wall id -> configurations it is OPEN in
var _distance: Dictionary[Vector2i, int] = {}
# Leaf clumps of every hedge that never moves, drawn as one MultiMesh.
var _leaves: Array[Transform3D] = []
var _leaf_colors: Array[Color] = []


func _output_path() -> String:
	return "res://scenes/levels/level_1_maze/level_1.tscn"


func _build() -> void:
	_root.name = "Level1"
	_root.set_script(LEVEL_SCRIPT)
	_root.set("level_id", &"level_1")
	_root.set("time_limit", 360.0)
	_root.set("autostart", false)
	_materials()
	# Daylight: the game is played in the open, in full view of a blue sky.
	_environment(0.008, Color(0.55, 0.60, 0.66), 1.1, 1.0, 1.0, "day")
	_generate_maze()
	_place_gates()
	_build_shell()
	_build_walls()
	_build_props()
	_systems()


func _materials() -> void:
	# A clipped formal garden at midday. Hedges are a dark core (the shade
	# deep inside the bush) under overlapping leaf clumps; the leaf texture is
	# cellular noise at leaf scale, tinted per clump by the MultiMesh colour.
	_m.hedge = _leaf_material()
	# The core shows in the gaps between clumps: the same leaf, in shade.
	_m.hedge_core = _m.hedge.duplicate()
	var core := _m.hedge_core as StandardMaterial3D
	core.albedo_color = Color(0.42, 0.48, 0.4)
	core.uv1_triplanar = true # a box has no useful UVs of its own
	core.uv1_world_triplanar = true
	core.uv1_scale = Vector3.ONE * 2.2
	_m.grass = _textured(Color(0.10, 0.26, 0.07), Color(0.38, 0.58, 0.20), 0.55, 92, 0.95, Vector3.ONE * 0.9)
	_m.gravel = _textured(Color(0.40, 0.38, 0.34), Color(0.68, 0.66, 0.60), 0.35, 98, 0.9, Vector3.ONE * 0.9)
	_m.stone = _textured(Color(0.46, 0.45, 0.42), Color(0.78, 0.77, 0.73), 0.02, 93, 0.9, Vector3.ONE * 0.35)
	_m.floor = _m.grass
	_m.metal = _textured(Color(0.05, 0.05, 0.06), Color(0.16, 0.16, 0.17), 0.03, 95, 0.45, Vector3.ONE, {"metallic": 0.8})
	_m.card = _flat(Color(0.9, 0.9, 0.88), 0.45)
	_m.glass_lamp = _flat(Color(0.75, 0.78, 0.72), 0.25, {"metallic": 0.2})
	_m.pipe = _flat(Color(0.14, 0.14, 0.13), 0.6, {"metallic": 0.7})
	_m.bulb = _emissive(Color(1.0, 0.85, 0.55), 6.0)
	_m.red_lamp = _emissive(BLOOD_RED, 6.0)
	_m.screen = _emissive(Color(0.03, 0.02, 0.02), 1.0)


func _leaf_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.seed = 91
	noise.frequency = 0.05
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var albedo := NoiseTexture2D.new()
	albedo.width = 512
	albedo.height = 512
	albedo.seamless = true
	albedo.noise = noise
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.36, 0.60, 0.18))
	gradient.set_color(1, Color(0.03, 0.10, 0.02))
	albedo.color_ramp = gradient
	var normal := NoiseTexture2D.new()
	normal.width = 512
	normal.height = 512
	normal.seamless = true
	normal.noise = noise
	normal.as_normal_map = true
	normal.bump_strength = 8.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.vertex_color_use_as_albedo = true # per-clump tint from the MultiMesh
	m.roughness = 0.9
	m.normal_enabled = true
	m.normal_texture = normal
	m.normal_scale = 0.8
	# The clumps' own sphere UVs, not triplanar: thousands of overlapping
	# clumps fill the screen, and triplanar reads every texture three times.
	m.uv1_scale = Vector3(5.0, 2.5, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


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


## Fisher-Yates on the seeded generator: Array.shuffle() uses the global one,
## which made every rebuild produce a different maze.
func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: Variant = array[i]
		array[i] = array[j]
		array[j] = swap


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
	_shuffle(candidates)

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
		_shuffle(candidates)
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
	var outer := span * 0.5 + 10.0
	var arch := CSGCombiner3D.new()
	arch.use_collision = true
	_add(_root, arch, "Architecture")
	# Lawn, and nothing overhead: the maze is cut into a garden, not a building.
	# It runs well past the garden wall so no gap ever looks out on the void.
	_csg(arch, "Lawn", Vector3(0, -0.1, 0), Vector3(outer * 2.0 + 40.0, 0.2, outer * 2.0 + 40.0), _m.grass)
	_csg(arch, "WalkSouth", Vector3(0, 0.02, span * 0.5 + 5.0), Vector3(CELL * 1.25, 0.12, 12.0), _m.gravel)
	_csg(arch, "WalkNorth", Vector3(0, 0.02, -(span * 0.5 + 5.0)), Vector3(CELL * 1.25, 0.12, 12.0), _m.gravel)

	# A garden wall around the grounds: the player is outdoors, but not free.
	var wall_h := 4.4
	for side: int in 4:
		var horizontal := side < 2
		var sign := 1.0 if side % 2 == 0 else -1.0
		var centre := Vector3(0, wall_h * 0.5, outer * sign) if horizontal else Vector3(outer * sign, wall_h * 0.5, 0)
		var size := Vector3(outer * 2.0 + 1.0, wall_h, 1.0) if horizontal else Vector3(1.0, wall_h, outer * 2.0 + 1.0)
		_csg(arch, "GardenWall", centre, size, _m.stone)
	# Gaps for the two gravel walks so the walls do not seal the garden off.
	_csg(arch, "WalkGapS", Vector3(0, wall_h * 0.5, outer), Vector3(CELL * 1.3, wall_h + 0.4, 2.4), _m.stone, true)
	_csg(arch, "WalkGapN", Vector3(0, wall_h * 0.5, -outer), Vector3(CELL * 1.3, wall_h + 0.4, 2.4), _m.stone, true)
	_iron_gate(_root, "GardenGateS", Vector3(0, 0, outer), CELL * 1.3, wall_h - 0.4)
	_iron_gate(_root, "GardenGateN", Vector3(0, 0, -outer), CELL * 1.3, wall_h - 0.4)

	# Entrance and exit are hedge corridors with stone pillars.
	var entrance := _cell_center(START) + Vector3(0, 0, CELL * 1.6)
	_hedge_run(arch, entrance + Vector3(-CELL * 0.6, 0, 0), Vector3(WALL, HEIGHT, CELL * 2.2))
	_hedge_run(arch, entrance + Vector3(CELL * 0.6, 0, 0), Vector3(WALL, HEIGHT, CELL * 2.2))
	var exit_center := _cell_center(EXIT) - Vector3(0, 0, CELL * 1.6)
	_hedge_run(arch, exit_center + Vector3(-CELL * 0.6, 0, 0), Vector3(WALL, HEIGHT, CELL * 2.4))
	_hedge_run(arch, exit_center + Vector3(CELL * 0.6, 0, 0), Vector3(WALL, HEIGHT, CELL * 2.4))
	for pillar: Vector3 in [entrance + Vector3(-CELL * 0.6, 0, CELL * 1.1),
			entrance + Vector3(CELL * 0.6, 0, CELL * 1.1),
			exit_center + Vector3(-CELL * 0.6, 0, -CELL * 1.2),
			exit_center + Vector3(CELL * 0.6, 0, -CELL * 1.2)]:
		_box(_root, "Pillar", Vector3(0.5, HEIGHT + 0.9, 0.5), pillar + Vector3(0, (HEIGHT + 0.9) * 0.5, 0), _m.stone)
		_mesh(_root, "PillarCap", _sphere(0.32), pillar + Vector3(0, HEIGHT + 1.1, 0), _m.stone)
	# The way in locks behind the player: the only way out is through the maze.
	_iron_gate(_root, "EntranceGate", entrance + Vector3(0, 0, CELL * 1.1), CELL * 1.2 - WALL, HEIGHT + 0.3)

	# The suits of this game, on a card-white board over the maze threshold,
	# facing the player as they arrive.
	var threshold := _cell_center(START) + Vector3(0, 0, CELL * 0.5 + 0.2)
	_box(_root, "EntranceBeam", Vector3(CELL * 1.5, 0.16, 0.16), threshold + Vector3(0, HEIGHT + 0.3, 0), _m.metal, false)
	_box(_root, "EntranceSign", Vector3(1.6, 0.8, 0.06), threshold + Vector3(0, HEIGHT + 0.78, 0), _m.card, false)
	_label(_root, "♦  ♣", threshold + Vector3(0, HEIGHT + 0.78, 0.04), Vector3.ZERO, 120, 0.005, Color(0.5, 0.05, 0.05))

	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = entrance + Vector3(0, 0.05, CELL * 0.7)


## One run of hedge standing on `base` (ground level): a stone kerb, a dark
## core, and leaf clumps over it (added to the shared foliage MultiMesh). The
## collider is the full leafy outline, so the player brushes the leaves
## instead of sinking into them.
func _hedge_run(parent: Node, base: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	_add(parent, body, "Hedge").position = base
	var outline := _leafy_size(size)
	_box_shape(body, Vector3(outline.x, size.y, outline.z), Vector3(0, size.y * 0.5, 0))
	var kerb := outline + _thin_axis(size) * 0.08 # a lip of stone peeks out under the leaves
	kerb.y = KERB
	_box(body, "Kerb", kerb, Vector3(0, KERB * 0.5, 0), _m.stone, false)
	_box(body, "Core", Vector3(size.x, size.y - KERB, size.z), Vector3(0, KERB + (size.y - KERB) * 0.5, 0), _m.hedge_core, false)
	_leaf_clumps(base, size, KERB, _leaves, _leaf_colors, Color.WHITE)


## Unit vector along a hedge's thin side (x for a north-south run).
func _thin_axis(size: Vector3) -> Vector3:
	return Vector3.RIGHT if size.x < size.z else Vector3.BACK


## A hedge's size with its leaves on.
func _leafy_size(size: Vector3) -> Vector3:
	return size + _thin_axis(size) * LEAF_DEPTH * 2.0


## Scatters leaf clumps over both long faces, both ends and the top of a hedge
## whose footprint is centred on `origin` (ground level). Clumps start at
## `bottom` and round over the top edge, so the silhouette is soft and uneven.
func _leaf_clumps(origin: Vector3, size: Vector3, bottom: float, transforms: Array[Transform3D],
		colors: Array[Color], tint: Color) -> void:
	var side := _thin_axis(size)
	var along := Vector3.BACK if side == Vector3.RIGHT else Vector3.RIGHT
	var length := size.dot(along)
	var thick := size.dot(side)
	var columns := maxi(1, roundi(length / LEAF_SPACING))
	var rows := maxi(1, roundi((size.y - bottom) / LEAF_SPACING))
	var step_u := length / columns
	var step_v := (size.y - bottom) / rows
	for face: float in [-1.0, 1.0]:
		for c in columns:
			for r in rows:
				# Staggered like brickwork, then jittered, so no grid shows.
				var u := -length * 0.5 + (c + 0.25 + 0.5 * (r % 2)) * step_u + _rng.randf_range(-0.14, 0.14)
				var v := bottom + (r + 0.5) * step_v + _rng.randf_range(-0.1, 0.1)
				var out := thick * 0.5 + _rng.randf_range(0.0, 0.06)
				_leaf_clump(origin + along * u + Vector3.UP * v + side * face * out,
					_rng.randf_range(0.3, 0.42), side, transforms, colors, tint)
		# The ends: a hedge that stops in a dead end is leafy there too.
		for r in rows:
			var v := bottom + (r + 0.5) * step_v + _rng.randf_range(-0.08, 0.08)
			_leaf_clump(origin + along * face * length * 0.5 + Vector3.UP * v,
				_rng.randf_range(0.3, 0.38), along, transforms, colors, tint)
	# The crown, wide enough to round over both top edges.
	for c in columns:
		var u := -length * 0.5 + (c + 0.5) * step_u + _rng.randf_range(-0.1, 0.1)
		var top := origin + along * u + Vector3.UP * (size.y + _rng.randf_range(-0.04, 0.06)) \
			+ side * _rng.randf_range(-0.05, 0.05)
		_leaf_clump(top, _rng.randf_range(0.34, 0.44), Vector3.UP, transforms, colors, tint)


## One clump: a sphere squashed along `normal` (it hugs the face it grows
## from), with a slightly different green from its neighbours.
func _leaf_clump(center: Vector3, radius: float, normal: Vector3, transforms: Array[Transform3D],
		colors: Array[Color], tint: Color) -> void:
	var scale := Vector3.ONE * radius - normal.abs() * radius * 0.45
	transforms.append(Transform3D(Basis.from_scale(scale), center))
	var shade := _rng.randf_range(0.0, 1.0)
	var green := Color(0.62, 0.70, 0.56).lerp(Color(1.0, 1.0, 0.9), shade)
	if _rng.randf() < 0.08:
		green = Color(0.85, 1.0, 0.6) # a sun-caught sprig of new growth
	colors.append(green * tint)


## Builds one LeafCover (a MultiMeshInstance3D) out of collected leaf clumps.
func _foliage(parent: Node, node_name: String, transforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var clump := SphereMesh.new()
	clump.radius = 1.0
	clump.height = 2.0
	clump.radial_segments = 9
	clump.rings = 5
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = clump
	# set_instance_transform() would be lost: headless there is no
	# RenderingServer to hold it. LeafCover uploads this buffer on load.
	var data := PackedFloat32Array()
	for i in transforms.size():
		var t := transforms[i]
		var c := colors[i]
		data.append_array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
			t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y,
			t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z,
			c.r, c.g, c.b, c.a])
	var instance := MultiMeshInstance3D.new()
	instance.set_script(LEAF_COVER)
	instance.multimesh = multimesh
	instance.material_override = _m.hedge
	# The hedge cores cast the shadows; thousands of clumps doing it too
	# would double the cost for a difference nobody sees.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set("instances", data)
	_add(parent, instance, node_name)
	return instance


## Wrought-iron gate standing on `base` (ground level), facing along z.
func _iron_gate(parent: Node, node_name: String, base: Vector3, width: float, height: float) -> void:
	var gate := StaticBody3D.new()
	_add(parent, gate, node_name).position = base
	_box_shape(gate, Vector3(width, height, 0.14), Vector3(0, height * 0.5, 0))
	for y: float in [0.15, height - 0.1]:
		_box(gate, "Rail", Vector3(width, 0.08, 0.08), Vector3(0, y, 0), _m.metal, false)
	var bars := int(width / 0.16)
	for i in bars + 1:
		var x := -width * 0.5 + width * i / bars
		_mesh(gate, "Bar", _cylinder(0.02, height), Vector3(x, height * 0.5, 0), _m.metal)
		_mesh(gate, "Finial", _sphere(0.04), Vector3(x, height + 0.04, 0), _m.metal)


func _build_walls() -> void:
	var walls := _group(_root, "Walls")
	var gates := _group(_root, "Gates")
	_unique.append(gates)
	for id: String in _walls:
		if not _walls[id]:
			continue
		var placement := _wall_transform(id)
		var size: Vector3 = placement[1]
		var base: Vector3 = placement[0] - Vector3(0, size.y * 0.5, 0)
		_hedge_run(walls, base, size)
	# Every fixed hedge's leaves (the entrance and exit runs included), in a
	# 3x3 grid of chunks: one draw call each, and the chunks off-screen are
	# culled instead of drawing every clump in the garden every frame.
	var chunk_size := CELLS * CELL / 3.0
	var chunks: Dictionary[Vector2i, Array] = {}
	for i in _leaves.size():
		var at := _leaves[i].origin
		var key := Vector2i(clampi(floori(at.x / chunk_size + 1.5), 0, 2), clampi(floori(at.z / chunk_size + 1.5), 0, 2))
		if not chunks.has(key):
			chunks[key] = [[] as Array[Transform3D], [] as Array[Color]]
		chunks[key][0].append(_leaves[i])
		chunks[key][1].append(_leaf_colors[i])
	for key: Vector2i in chunks:
		_foliage(walls, "Leaves", chunks[key][0], chunks[key][1])
	for id: String in _gates:
		var placement := _wall_transform(id)
		var gate := Node3D.new()
		gate.set_script(MAZE_GATE)
		gate.set("open_in", _gates[id])
		gate.set("travel", HEIGHT + 0.6) # deep enough to bury the crown too
		_add(gates, gate, "Gate")
		var panel := AnimatableBody3D.new()
		_add(gate, panel, "Panel")
		panel.position = placement[0]
		var size: Vector3 = placement[1]
		var outline := _leafy_size(size)
		_box(panel, "Core", size - Vector3(0, 0.1, 0), Vector3(0, 0.05, 0), _m.hedge_core, false)
		_box_shape(panel, outline, Vector3.ZERO)
		# A moving hedge has no kerb, a darker, bluer leaf, and a string of
		# lamps along its crown, so it reads as different from one that cannot.
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		_leaf_clumps(Vector3(0, -size.y * 0.5, 0), size, 0.1, transforms, colors, Color(0.72, 0.8, 0.82))
		_foliage(panel, "Leaves", transforms, colors)
		var along := Vector3.BACK if _thin_axis(size) == Vector3.RIGHT else Vector3.RIGHT
		for i in 7:
			var u := (i - 3) * CELL / 7.0
			_mesh(panel, "Lamp", _sphere(0.05), along * u + Vector3.UP * (size.y * 0.5 + 0.34), _m.bulb)


func _build_props() -> void:
	var span := (CELLS - 1) * 0.5 * CELL
	# Midday sun. Everything in this maze is lit, which is the point: the
	# danger is the walls moving, not the dark.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	_add(_root, sun, "Sunlight").rotation_degrees = Vector3(-52, 38, 0)

	# Garden lanterns, unlit at this hour: dressing tucked into the hedge
	# corners so they never block a passage.
	var lights := _group(_root, "MazeLights")
	for cx in range(0, CELLS, 2):
		for cz in range(0, CELLS, 2):
			var cell := Vector2i(cx, cz)
			var corner := CELL * 0.5 - WALL * 0.5 - LEAF_DEPTH - 0.12 # just clear of the leaves
			var foot: Vector3 = _cell_center(cell) + Vector3(-corner, 0.0, -corner)
			_mesh(lights, "LanternPost", _cylinder(0.05, 2.1), foot + Vector3(0, 1.05, 0), _m.pipe)
			_mesh(lights, "LanternGlass", _sphere(0.11), foot + Vector3(0, 2.2, 0), _m.glass_lamp)

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
		# A plinth, so the stone sits on something rather than floating in daylight.
		_mesh(stone, "Plinth", _cylinder(0.2, 0.36), Vector3(0, 0.18, 0), _m.stone)

	# Laser tripwires across open passages, away from the entrance.
	var lasers := _group(_root, "Lasers")
	_unique.append(lasers)
	var open_ids: Array[String] = []
	for id: String in _walls:
		if not _walls[id] and not _gates.has(id):
			open_ids.append(id)
	_shuffle(open_ids)
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
		# Sinks into the lawn like the maze gates: with no ceiling, a door that
		# rose would hang in the sky and pass through the arch.
		{"slide_offset": Vector3(0, -HEIGHT, 0), "open_time": 2.2, "interactive": false,
		"open_sound": &"shutter", "player_can_close": false})
	_unique.append(door)
	# Iron arch over the way out, with a dark board so the sign reads against
	# the sky. Faces south, towards the maze the player is coming from.
	_box(_root, "ArchBeam", Vector3(CELL * 1.5, 0.16, 0.16), exit_center + Vector3(0, HEIGHT + 0.3, 0), _m.metal, false)
	_box(_root, "ExitSign", Vector3(1.3, 0.55, 0.06), exit_center + Vector3(0, HEIGHT + 0.66, 0), _m.metal, false)
	_label(_root, "EXIT", exit_center + Vector3(0, HEIGHT + 0.66, 0.04), Vector3.ZERO, 96, 0.004, Color(0.2, 0.9, 0.4))
	_omni(_root, "ExitLight", _cell_center(EXIT) - Vector3(0, -2.4, CELL * 2.4), Color(0.7, 1.0, 0.8), 2.0, 6.0, false, Light.STEADY)
	_trigger(_root, "ExitTrigger", _cell_center(EXIT) - Vector3(0, -1.0, CELL * 2.2), Vector3(CELL, 2.0, 1.0))

	# Garden dressing: topiary and urns in the corners of random cells.
	var dressing := _group(_root, "Dressing")
	for i in 14:
		var cell := Vector2i(_rng.randi_range(0, CELLS - 1), _rng.randi_range(0, CELLS - 1))
		if cell == START or cell == EXIT:
			continue
		var sx := 1.0 if _rng.randf() < 0.5 else -1.0
		var sz := 1.0 if _rng.randf() < 0.5 else -1.0
		if sx < 0.0 and sz < 0.0 and cell.x % 2 == 0 and cell.y % 2 == 0:
			sx = 1.0 # that corner already holds a lantern
		var topiary := _rng.randf() < 0.55
		var radius := _rng.randf_range(0.32, 0.42) if topiary else 0.36
		# Inset so the widest part stops short of the leaves (and any gate).
		var inset := CELL * 0.5 - WALL * 0.5 - LEAF_DEPTH - 0.1 - radius
		var spot: Vector3 = _cell_center(cell) + Vector3(sx * inset, 0.0, sz * inset)
		var body := StaticBody3D.new()
		_add(dressing, body, "Topiary" if topiary else "Urn").position = spot
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.3
		cylinder.height = 1.0
		shape.shape = cylinder
		_add(body, shape, "Shape").position = Vector3(0, 0.5, 0)
		if topiary:
			_mesh(body, "Ball", _sphere(radius), Vector3(0, radius + 0.25, 0), _m.hedge)
			_mesh(body, "Pot", _cylinder(0.26, 0.5), Vector3(0, 0.25, 0), _m.stone)
		else:
			_mesh(body, "Body", _cylinder(0.3, 0.9), Vector3(0, 0.45, 0), _m.stone)
			_mesh(body, "Lip", _cylinder(0.36, 0.12), Vector3(0, 0.92, 0), _m.stone)

	# Entrance dressing: the cards from the hub keep leading the way in.
	for i in 5:
		_card(_root, _cell_center(START) + Vector3(_rng.randf_range(-1.0, 1.0), 0.02, CELL * (1.0 + i * 0.35)), i)


func _systems() -> void:
	_add_core_systems(1.0, &"music_level_1")
	# Outdoors in daylight the usual vignette and desaturation read as haze
	# over a grey sky, so this level wears them lightly.
	var fx: CanvasLayer = _root.get_node("HorrorFX")
	fx.set("base_vignette", 0.18)
	fx.set("desaturation", 0.05)
	fx.set("base_grain", 0.03)
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
