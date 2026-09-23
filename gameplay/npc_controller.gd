class_name NPCController
extends CharacterBody3D
## Modular AI companion / bystander built on the same rig as the player.
##
## States: IDLE, WALK, RUN, HIDE, INTERACT — driven by simple commands
## (`go_to`, `operate`, `hold_position`, `hide_at`), so any level can script
## an NPC without new movement code. Stats (fear / selfishness / trust) shape
## how they react: a frightened NPC hesitates, a selfish one may refuse, and
## trust decides whether they do what you ask at all.

signal state_changed(new_state: State)
signal reached_target
signal command_refused(reason: StringName)
signal interaction_finished(target: Node3D)

enum State { IDLE, WALK, RUN, HIDE, INTERACT }

const MODEL := preload("res://Simple_Character_PSX/model/glb/simple-character-psx.glb")
const ANIMATIONS := preload("res://player/animations/player_animations.res")
const WALK_STRIDE := 1.44
const RUN_STRIDE := 3.24

@export var npc_name := "NPC"
@export var tint := Color(0.4, 0.6, 0.9)
@export_range(0, 10) var fear := 4
@export_range(0, 10) var selfishness := 3
@export_range(0, 10) var trust := 6
@export var walk_speed := 1.6
@export var run_speed := 4.0
@export var arrive_distance := 0.55
@export var show_name := true

var state: State = State.IDLE

var _model: Node3D
var _anim: AnimationPlayer
var _name_tag: Label3D
var _target: Vector3
var _has_target := false
var _interact_target: Node3D
var _interact_time := 0.0
var _current_anim: StringName = &""


func _ready() -> void:
	collision_layer = Layers.NPC
	collision_mask = Layers.WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.9
	shape.shape = capsule
	shape.position = Vector3(0, 0.95, 0)
	add_child(shape)

	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	_tint_body()
	_anim = AnimationPlayer.new()
	_model.add_child(_anim)
	_anim.add_animation_library(&"", ANIMATIONS)
	_play(&"idle", 1.0)

	if show_name:
		_name_tag = Label3D.new()
		_name_tag.text = npc_name
		_name_tag.font_size = 40
		_name_tag.pixel_size = 0.0028
		_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_name_tag.modulate = tint.lightened(0.35)
		_name_tag.outline_size = 8
		_name_tag.position = Vector3(0, 2.15, 0)
		add_child(_name_tag)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	match state:
		State.WALK, State.RUN:
			_move_to_target(delta)
		State.INTERACT:
			_interact_time -= delta
			if _interact_time <= 0.0:
				_set_state(State.IDLE)
				interaction_finished.emit(_interact_target)
		_:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	move_and_slide()
	_update_animation()


# =========================================================================
# Commands
# =========================================================================

## Walk (or run) to a point. Returns false if they refuse to move.
func go_to(target: Vector3, run: bool = false) -> bool:
	if not _accepts_command():
		command_refused.emit(&"distrust")
		return false
	_target = target
	_has_target = true
	_set_state(State.RUN if run or fear >= 8 else State.WALK)
	return true


## Walk to `target` and work on it for `duration` seconds (valve, switch, door).
func operate(target: Node3D, duration: float = 1.2) -> bool:
	if not _accepts_command():
		command_refused.emit(&"distrust")
		return false
	_interact_target = target
	_interact_time = duration
	if global_position.distance_to(target.global_position) > arrive_distance * 2.0:
		if not go_to(_operating_spot(target)):
			return false
		# _move_to_target() switches to INTERACT once we arrive.
		return true
	_face(target.global_position)
	_set_state(State.INTERACT)
	return true


## Stand still on a spot and keep standing there (pressure plates, levers).
func hold_position(target: Vector3) -> bool:
	if not _accepts_command():
		command_refused.emit(&"distrust")
		return false
	_interact_target = null
	_target = target
	_has_target = true
	_set_state(State.WALK)
	return true


func hide_at(spot: Vector3) -> void:
	_target = spot
	_has_target = true
	_set_state(State.RUN)
	_interact_target = null
	# HIDE is entered on arrival.
	_interact_time = -1.0


func stop() -> void:
	_has_target = false
	_set_state(State.IDLE)


func change_stat(stat: StringName, amount: int) -> void:
	set(stat, clampi(int(get(stat)) + amount, 0, 10))


## Frightened, selfish and distrustful NPCs stop following orders.
func _accepts_command() -> bool:
	return trust + (10 - selfishness) >= 6 and fear < 9


# =========================================================================
# Movement
# =========================================================================

func _move_to_target(delta: float) -> void:
	if not _has_target:
		_set_state(State.IDLE)
		return
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() <= arrive_distance:
		_has_target = false
		velocity.x = 0.0
		velocity.z = 0.0
		if _interact_time > 0.0 and _interact_target:
			_face(_interact_target.global_position)
			_set_state(State.INTERACT)
		elif _interact_time < 0.0:
			_set_state(State.HIDE)
		else:
			_set_state(State.IDLE)
		reached_target.emit()
		return
	var speed := run_speed if state == State.RUN else walk_speed
	var direction := to_target.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-8.0 * delta))


## A spot just in front of the thing they are going to work on.
func _operating_spot(target: Node3D) -> Vector3:
	var offset := (global_position - target.global_position)
	offset.y = 0.0
	if offset.length() < 0.1:
		offset = Vector3.BACK
	return target.global_position + offset.normalized() * arrive_distance * 1.5


func _face(point: Vector3) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(to.x, to.z)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(new_state)


func _update_animation() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	match state:
		State.INTERACT:
			_play(&"idle_tense", 1.2)
		State.HIDE:
			_play(&"crouch_idle", 1.0)
		_:
			if speed > 2.6:
				_play(&"run", speed / RUN_STRIDE)
			elif speed > 0.2:
				_play(&"walk", speed / WALK_STRIDE)
			elif fear >= 6:
				_play(&"idle_tense", 1.0 + fear * 0.05)
			else:
				_play(&"idle", 1.0)


func _play(anim_name: StringName, speed: float) -> void:
	if anim_name != _current_anim:
		_current_anim = anim_name
		_anim.play(anim_name, 0.4)
	_anim.speed_scale = speed


func _tint_body() -> void:
	var body := _model.find_child("body", true, false) as MeshInstance3D
	if body == null:
		return
	for surface in body.get_surface_override_material_count():
		var material := body.get_active_material(surface) as StandardMaterial3D
		if material:
			var tinted := material.duplicate() as StandardMaterial3D
			tinted.albedo_color = Color.WHITE.lerp(tint, 0.55)
			body.set_surface_override_material(surface, tinted)
