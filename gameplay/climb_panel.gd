class_name ClimbPanel
extends Area3D
## A section of climbing wall (Level 3). The player's ClimbAbility attaches
## while inside this area and can move freely over its face.
##
## Blue panels are solid. Orange ones are rigged: `break_delay` seconds after
## the player grabs on, the holds tear out of the wall and the panel drops —
## so you have to keep moving upward.

signal broke(panel: ClimbPanel)

const SOLID := Color(0.25, 0.65, 1.0)
const FRAGILE := Color(1.0, 0.45, 0.08)

@export var breakable := false
@export var break_delay := 3.0
@export var size := Vector2(3.0, 5.0) ## width x height of the climbable face
@export var hold_rows := 5
@export var hold_columns := 3

var is_broken := false

var _holds: Array[MeshInstance3D] = []
var _timer := 0.0
var _armed := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	add_to_group(&"climbable") # ClimbAbility looks for these
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# The volume reaches out from the wall so the player can grab it.
	box.size = Vector3(size.x, size.y, 0.9)
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0.35)
	add_child(shape)
	_build_holds()
	set_process(false)


func _process(delta: float) -> void:
	_timer -= delta
	# Warn with a faster and faster blink before it goes.
	var blink := 1.0 if fmod(_timer, maxf(_timer * 0.35, 0.12)) > maxf(_timer * 0.18, 0.06) else 0.25
	for hold in _holds:
		(hold.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 * blink
	if _timer <= 0.0:
		_break()


## Called by ClimbAbility the first time the player grabs this panel.
func touched() -> void:
	if not breakable or _armed or is_broken:
		return
	_armed = true
	_timer = break_delay
	set_process(true)


func _build_holds() -> void:
	var color := FRAGILE if breakable else SOLID
	var material := StandardMaterial3D.new()
	material.albedo_color = color * 0.5
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	for row in hold_rows:
		for column in hold_columns:
			var hold := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.12, 0.16)
			hold.mesh = box
			hold.material_override = material
			hold.position = Vector3(
				(column - (hold_columns - 1) * 0.5) * (size.x / hold_columns),
				0.45 + row * (size.y - 0.6) / maxi(hold_rows - 1, 1),
				0.06)
			hold.rotation_degrees.z = randf_range(-12.0, 12.0)
			add_child(hold)
			_holds.append(hold)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.position = Vector3(0, size.y * 0.5, 0.4)
	add_child(light)


func _break() -> void:
	is_broken = true
	set_process(false)
	monitoring = false
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(&"bang")
	sound.unit_size = 6.0
	add_child(sound)
	sound.play()
	for hold in _holds:
		var fall := create_tween()
		fall.tween_property(hold, "position:y", hold.position.y - 30.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.parallel().tween_property(hold, "position:x", hold.position.x + randf_range(-1.0, 1.0), 3.0)
	broke.emit(self)
