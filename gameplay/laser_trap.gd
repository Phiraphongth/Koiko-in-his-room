class_name LaserTrap
extends Node3D
## Automated alarm beam across a corridor.
##   CROUCH: always on, at chest height — walk into it and the alarm goes off,
##           crouch [C] and you pass underneath.
##   TIMED:  full height, blinks on and off; you have to time the gap.
## Emits `tripped` once per entry; Level 1 counts those as alarm strikes.

signal tripped(body: Node3D)

enum Mode { CROUCH, TIMED }

const BEAM_COLOR := Color(1.0, 0.1, 0.08)

@export var mode: Mode = Mode.CROUCH
@export var length := 3.2
@export var height := 1.65 ## beam height for CROUCH mode
@export var on_time := 2.2
@export var off_time := 1.8
@export var phase := 0.0 ## seconds of offset, so neighbouring beams differ

var is_armed := true

var _beam: MeshInstance3D
var _area: Area3D
var _material: StandardMaterial3D
var _hum: AudioStreamPlayer3D
var _timer := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = BEAM_COLOR
	_material.emission_enabled = true
	_material.emission = BEAM_COLOR
	_material.emission_energy_multiplier = 12.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_beam = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.012
	cylinder.bottom_radius = 0.012
	cylinder.height = length
	_beam.mesh = cylinder
	_beam.material_override = _material
	_beam.rotation_degrees.z = 90.0 # lie the beam across the corridor (local X)
	add_child(_beam)

	var glow := OmniLight3D.new()
	glow.light_color = BEAM_COLOR
	glow.light_energy = 0.8
	glow.omni_range = 3.0
	add_child(glow)

	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = Layers.PLAYER
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 0.14, 0.14)
	shape.shape = box
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)

	_hum = AudioStreamPlayer3D.new()
	_hum.bus = "SFX"
	_hum.stream = ProceduralAudio.get_stream(&"laser")
	_hum.unit_size = 1.5
	_hum.max_distance = 12.0
	_hum.volume_db = -22.0
	add_child(_hum)
	_hum.play()

	position.y = height if mode == Mode.CROUCH else 1.0
	_timer = phase
	set_process(mode == Mode.TIMED)


func _process(delta: float) -> void:
	_timer += delta
	var cycle := on_time + off_time
	_set_armed(fmod(_timer, cycle) < on_time)


func disarm() -> void:
	_set_armed(false)
	set_process(false)
	_hum.stop()


func _set_armed(armed: bool) -> void:
	if armed == is_armed:
		return
	is_armed = armed
	_beam.visible = armed
	_area.monitoring = armed
	_hum.volume_db = -22.0 if armed else -80.0


func _on_body_entered(body: Node3D) -> void:
	if is_armed and body is Player:
		tripped.emit(body)
