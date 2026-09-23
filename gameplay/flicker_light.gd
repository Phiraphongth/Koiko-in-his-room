class_name FlickerLight
extends Light3D
## Horror light. Attach to an OmniLight3D or SpotLight3D.
## STEADY = on, FLICKER = constant unstable flicker, BROKEN = mostly on with
## random blackout bursts, OFF = dead. Optionally drives an emissive mesh
## (its material is duplicated per light) and a positional electrical hum.

enum Mode { STEADY, FLICKER, BROKEN, OFF }

@export var mode: Mode = Mode.STEADY:
	set(value):
		mode = value
		if is_node_ready():
			_enter_mode()
@export var on_energy := 2.0
@export var emissive_mesh: NodePath
@export var emission_energy := 4.0
@export var hum := false
@export var hum_volume_db := -20.0

var _mesh_material: StandardMaterial3D
var _hum_player: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _burst_left := 0
var _level := 1.0


func _ready() -> void:
	_rng.randomize()
	var mesh := get_node_or_null(emissive_mesh) as GeometryInstance3D
	if mesh and mesh.material_override is StandardMaterial3D:
		_mesh_material = mesh.material_override.duplicate()
		mesh.material_override = _mesh_material
	if hum:
		_hum_player = AudioStreamPlayer3D.new()
		_hum_player.bus = "SFX"
		_hum_player.stream = ProceduralAudio.get_stream(&"hum")
		_hum_player.unit_size = 2.0
		_hum_player.max_distance = 14.0
		_hum_player.volume_db = hum_volume_db
		add_child(_hum_player)
		_hum_player.play()
	_enter_mode()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if mode == Mode.FLICKER:
		_timer = _rng.randf_range(0.03, 0.12)
		_apply(1.0 if _rng.randf() > 0.45 else _rng.randf_range(0.0, 0.3))
	elif _burst_left > 0: # BROKEN, mid-burst
		_burst_left -= 1
		_apply(0.0 if _level > 0.5 else 1.0)
		_timer = _rng.randf_range(0.03, 0.14)
		if _burst_left == 0:
			_apply(1.0)
			_timer = _rng.randf_range(2.0, 7.0)
	else: # BROKEN, start a burst
		_burst_left = _rng.randi_range(3, 9)


func turn_off(with_pop: bool = true) -> void:
	if with_pop and _level > 0.1:
		_play_one_shot(&"pop")
	mode = Mode.OFF


func turn_on(new_mode: Mode = Mode.STEADY) -> void:
	mode = new_mode


func _enter_mode() -> void:
	set_process(mode == Mode.FLICKER or mode == Mode.BROKEN)
	_burst_left = 0
	match mode:
		Mode.OFF:
			_apply(0.0)
		Mode.BROKEN:
			_apply(1.0)
			_timer = _rng.randf_range(0.5, 4.0)
		_:
			_apply(1.0)


func _apply(level: float) -> void:
	_level = level
	light_energy = on_energy * level
	if _mesh_material:
		_mesh_material.emission_energy_multiplier = emission_energy * level
	if _hum_player:
		_hum_player.volume_db = hum_volume_db if level > 0.5 else -80.0


func _play_one_shot(id: StringName) -> void:
	var player := AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.stream = ProceduralAudio.get_stream(id)
	player.unit_size = 3.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
