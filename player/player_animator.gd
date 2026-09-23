class_name PlayerAnimator
extends Node
## Drives the character model from Player state. Child of Player.
##
## Layers (bottom to top):
##  1. AnimationTree (built in code): idle/tense/exhausted stand pose,
##     phase-synced walk<->run, crouch, jump/fall, land one-shot.
##     Locomotion playback rate = speed / stride length -> no foot sliding.
##  2. Procedural body lean into turns and acceleration.
##  3. LookAtModifier3D: head follows where the camera is looking.
##  4. Breathing speed follows heart rate (scared = fast breathing).

const LIBRARY := preload("res://player/animations/player_animations.res")
# Hip travel per 1-second normalized cycle; must match build_player_animations.gd.
const WALK_STRIDE := 1.44
const RUN_STRIDE := 3.24
const CROUCH_STRIDE := 0.9

@export var model_path: NodePath = ^"../Visual/Model"
@export var blend_sharpness := 8.0
@export_group("Lean")
@export var max_lean_deg := 10.0
@export var turn_lean := 0.12 ## degrees per (rad/s * m/s)
@export var accel_lean := 1.2 ## degrees per m/s^2
@export_group("Head Look")
@export var head_look := true
@export var head_bone := "spine.005"
@export var head_yaw_limit_deg := 60.0
@export var head_pitch_limit_deg := 35.0
@export_group("Air")
@export var fall_delay := 0.15 ## seconds airborne before switching to fall (ignores small steps)
@export var land_min_speed := 3.0

@onready var _player: Player = get_parent() as Player
@onready var _model: Node3D = get_node(model_path) as Node3D
@onready var _visual: Node3D = _model.get_parent() as Node3D

var _tree: AnimationTree
var _skeleton: Skeleton3D
var _look: LookAtModifier3D
var _look_target: Marker3D
var _model_base: Basis

var _run_blend := 0.0
var _move_blend := 0.0
var _crouch_blend := 0.0
var _crouch_move_blend := 0.0
var _tense_blend := 0.0
var _exhaust_blend := 0.0
var _lean := Vector2.ZERO # x = pitch, y = roll (radians)
var _last_yaw := 0.0
var _last_hvel := Vector3.ZERO
var _air_time := 0.0
var _peak_fall_speed := 0.0
var _air_state := &"ground"


func _ready() -> void:
	_model_base = _model.basis
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_build_tree()
	if head_look and _skeleton:
		_build_head_look()
	_last_yaw = _visual.rotation.y


func _process(delta: float) -> void:
	var hvel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var speed := hvel.length()
	if _player.state == Player.State.DISABLED or _player.state == Player.State.HIDDEN:
		speed = 0.0
	var k := 1.0 - exp(-blend_sharpness * delta)

	# --- Ground locomotion ---
	_run_blend = lerpf(_run_blend, clampf(inverse_lerp(_player.walk_speed, _player.run_speed, speed), 0.0, 1.0), k)
	_move_blend = lerpf(_move_blend, clampf(speed / (_player.walk_speed * 0.5), 0.0, 1.0), k)
	var stride := lerpf(WALK_STRIDE, RUN_STRIDE, _run_blend)
	_set_blend(&"move", _run_blend)
	_set_blend(&"ground", _move_blend)
	_tree.set(&"parameters/move_rate/scale", maxf(speed, 0.3) / stride)

	# --- Crouch ---
	_crouch_blend = lerpf(_crouch_blend, 1.0 if _player.is_crouching else 0.0, k)
	_crouch_move_blend = lerpf(_crouch_move_blend, clampf(speed / (_player.crouch_speed * 0.5), 0.0, 1.0), k)
	_set_blend(&"posture", _crouch_blend)
	_set_blend(&"crouch_move", _crouch_move_blend)
	_tree.set(&"parameters/crouch_rate/scale", maxf(speed, 0.2) / CROUCH_STRIDE)

	# --- Stand pose: fear and exhaustion ---
	_tense_blend = lerpf(_tense_blend, _player.get_heartbeat_normalized(), k * 0.5)
	_exhaust_blend = lerpf(_exhaust_blend, 1.0 if _player.is_exhausted else 0.0, k * 0.5)
	_set_blend(&"tense", _tense_blend)
	_set_blend(&"exhaust", _exhaust_blend)
	_tree.set(&"parameters/breath_rate/scale", clampf(_player.heartbeat_bpm / _player.resting_bpm, 1.0, 2.5))

	_update_air(delta)
	_update_lean(delta, hvel, speed)
	_update_head_look(speed)


func _update_air(delta: float) -> void:
	var airborne := _player.state == Player.State.AIRBORNE
	if airborne:
		_air_time += delta
		_peak_fall_speed = maxf(_peak_fall_speed, -_player.velocity.y)
		if _player.velocity.y > 0.5:
			_request_air(&"jump")
		elif _air_time > fall_delay:
			_request_air(&"fall")
	else:
		if _air_state != &"ground":
			if _peak_fall_speed >= land_min_speed:
				_tree.set(&"parameters/land_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			_request_air(&"ground")
		_air_time = 0.0
		_peak_fall_speed = 0.0


func _request_air(state: StringName) -> void:
	if state != _air_state:
		_air_state = state
		_tree.set(&"parameters/air/transition_request", String(state))


## Leans into turns (centripetal) and forward/back with acceleration.
func _update_lean(delta: float, hvel: Vector3, speed: float) -> void:
	var yaw := _visual.rotation.y
	var turn_rate := angle_difference(_last_yaw, yaw) / maxf(delta, 0.0001)
	_last_yaw = yaw
	var accel := (hvel - _last_hvel) / maxf(delta, 0.0001)
	_last_hvel = hvel
	var forward := -_visual.global_basis.z
	var max_lean := deg_to_rad(max_lean_deg)
	var target := Vector2(
		clampf(-deg_to_rad(accel_lean) * accel.dot(forward), -max_lean, max_lean),
		clampf(-deg_to_rad(turn_lean) * turn_rate * speed, -max_lean, max_lean))
	if _player.state == Player.State.AIRBORNE:
		target = Vector2.ZERO
	_lean = _lean.lerp(target, 1.0 - exp(-6.0 * delta))
	_model.basis = Basis(Vector3.RIGHT, _lean.x) * Basis(Vector3.FORWARD, _lean.y) * _model_base


func _update_head_look(speed: float) -> void:
	if _look == null:
		return
	var camera := _player.get_camera()
	var aim := -camera.global_basis.z
	var body_forward := -_visual.global_basis.z
	var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(head_bone))
	_look_target.global_position = head.origin + aim * 5.0
	# Fade out when looking behind the character, while running, or hidden.
	var facing := clampf(inverse_lerp(-0.2, 0.4, aim.dot(body_forward)), 0.0, 1.0)
	var calm := 1.0 - clampf(inverse_lerp(_player.walk_speed, _player.run_speed, speed), 0.0, 1.0) * 0.7
	var active := _player.state != Player.State.HIDDEN and _player.state != Player.State.DISABLED
	var target_influence := facing * calm if active else 0.0
	_look.influence = lerpf(_look.influence, target_influence, 0.1)


func _set_blend(node: StringName, amount: float) -> void:
	_tree.set(StringName("parameters/%s/blend_amount" % node), amount)


# =========================================================================
# Construction
# =========================================================================

func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	for anim_name: StringName in [&"idle", &"idle_tense", &"exhausted", &"walk", &"run",
			&"crouch_idle", &"crouch_walk", &"jump", &"fall", &"land"]:
		var node := AnimationNodeAnimation.new()
		node.animation = anim_name
		bt.add_node(StringName("a_" + anim_name), node)

	# Stand: idle -> tense (fear) -> exhausted, breathing rate scaled by heartbeat.
	_add_blend2(bt, &"tense", &"a_idle", &"a_idle_tense")
	_add_blend2(bt, &"exhaust", &"tense", &"a_exhausted")
	_add_timescale(bt, &"breath_rate", &"exhaust")
	# Move: walk/run share a 1s normalized cycle, sync keeps them in phase.
	_add_blend2(bt, &"move", &"a_walk", &"a_run", true)
	_add_timescale(bt, &"move_rate", &"move")
	_add_blend2(bt, &"ground", &"breath_rate", &"move_rate")
	# Crouch.
	_add_timescale(bt, &"crouch_rate", &"a_crouch_walk")
	_add_blend2(bt, &"crouch_move", &"a_crouch_idle", &"crouch_rate")
	_add_blend2(bt, &"posture", &"ground", &"crouch_move")
	# Air.
	var air := AnimationNodeTransition.new()
	air.xfade_time = 0.15
	for input_name in ["ground", "jump", "fall"]:
		air.add_input(input_name)
	bt.add_node(&"air", air)
	bt.connect_node(&"air", 0, &"posture")
	bt.connect_node(&"air", 1, &"a_jump")
	bt.connect_node(&"air", 2, &"a_fall")
	# Landing impact.
	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.05
	land.fadeout_time = 0.2
	bt.add_node(&"land_shot", land)
	bt.connect_node(&"land_shot", 0, &"air")
	bt.connect_node(&"land_shot", 1, &"a_land")
	bt.connect_node(&"output", 0, &"land_shot")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.add_animation_library(&"", LIBRARY)
	_tree.tree_root = bt
	add_child(_tree)
	_tree.root_node = _tree.get_path_to(_model)
	_tree.active = true
	# A Transition has no current state until one is requested; without this
	# the whole tree outputs the rest (T) pose until the first jump.
	_tree.set(&"parameters/air/transition_request", "ground")


func _add_blend2(bt: AnimationNodeBlendTree, node_name: StringName, a: StringName, b: StringName, sync: bool = false) -> void:
	var blend := AnimationNodeBlend2.new()
	blend.sync = sync
	bt.add_node(node_name, blend)
	bt.connect_node(node_name, 0, a)
	bt.connect_node(node_name, 1, b)


func _add_timescale(bt: AnimationNodeBlendTree, node_name: StringName, source: StringName) -> void:
	bt.add_node(node_name, AnimationNodeTimeScale.new())
	bt.connect_node(node_name, 0, source)


func _build_head_look() -> void:
	_look_target = Marker3D.new()
	_look_target.name = "HeadLookTarget"
	_look_target.top_level = true
	add_child(_look_target)

	_look = LookAtModifier3D.new()
	_look.name = "HeadLook"
	_look.bone_name = head_bone
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_look.primary_rotation_axis = Vector3.AXIS_Y
	_look.use_secondary_rotation = true
	_look.relative = true
	_look.duration = 0.25
	_look.transition_type = Tween.TRANS_SINE
	_look.ease_type = Tween.EASE_IN_OUT
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(head_yaw_limit_deg * 2.0)
	_look.primary_damp_threshold = 0.7
	_look.secondary_limit_angle = deg_to_rad(head_pitch_limit_deg * 2.0)
	_look.secondary_damp_threshold = 0.7
	_look.influence = 0.0
	_skeleton.add_child(_look)
	_look.target_node = _look.get_path_to(_look_target)
