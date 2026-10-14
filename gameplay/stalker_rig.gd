class_name StalkerRig
extends Node3D
## The Stalker's body: the "Smily horror monster" model (CC-BY 4.0, Bento —
## see characters/smily_monster/CREDITS.txt) on all fours.
##
## The model ships with a single idle clip, so everything else is layered on
## top of it procedurally, every frame, in this order:
##  1. the idle clip (breathing, finger twitches, jaw chatter)
##  2. a crawl gait that blends from a creeping trot into a galloping bound
##  3. pose controls the AI / kill cutscene tween directly:
##     rear, lunge, jaw_open, jaw_stretch, head_roll, thrash, listen, look_at
##  4. random nervous head twitches
## Rotations are given in the rig's own space (X = its right, Y = up,
## Z = the way it faces) and converted into each bone's parent space, so the
## numbers below do not depend on how the original rig was built.

const MODEL := preload("res://characters/smily_monster/smily_horror_monster.glb")
const SCALE := 0.017 # model units -> metres: ~1.6 m tall on all fours, ~2 m long
const MODEL_CENTER := Vector3(-83.3, -1.6, 4.0) # floor-centre of the body, model units

const WALK_STRIDE := 1.0 # metres travelled per gait cycle while creeping
const GALLOP_STRIDE := 2.6 # ... and while charging
## Feeding arm pose (radians): reach forward, splay the elbows out like a
## spider, bend the forearm back, so the chest drops but the hands stay planted.
const FEED_ARM := Vector3(-0.75, 0.55, -0.5)

# --- Pose controls -------------------------------------------------------
var move_speed := 0.0 ## m/s along its facing; negative = backing up (dragging)
var rear := 0.0 ## 0 = on all fours, 1 = torso reared up, hands off the floor
var lunge := 0.0 ## head and neck thrust forward and down (strikes)
var feed := 0.0 ## chest down between the elbows, face to the floor (eating)
var jaw_open := 0.0 ## 1 = wide open, above 1 = past what a jaw should do
var jaw_stretch := 0.0 ## the unhinged jaw: lengthens the lower jaw
var head_roll := 0.0 ## radians; turns the head over like an owl
var thrash := 0.0 ## violent side-to-side shaking of the head (tearing)
var listen := 0.0 ## freezes and cocks the head to one side
var look_target := Vector3.ZERO ## world point the head turns to (look_weight > 0)
var look_weight := 0.0
var twitching := true ## random nervous jerks of the head
var idle_speed := 1.0

var _model: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _to_skeleton := Basis() # rig space -> skeleton space (rotation only)
var _base_position := Vector3.ZERO
var _driven: PackedInt32Array = []
var _bones: Dictionary[StringName, int] = {}
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _phase := 0.0
var _gait := 0.0 # amplitude 0..1
var _gallop := 0.0 # trot 0 .. bound 1
var _twitch := Vector3.ZERO # roll, yaw, pitch impulse
var _twitch_timer := 2.0


func _ready() -> void:
	_rng.randomize()
	_model = MODEL.instantiate() as Node3D
	_model.scale = Vector3.ONE * SCALE
	_base_position = -MODEL_CENTER * SCALE
	_model.position = _base_position
	add_child(_model)
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Rig space -> skeleton space, walking up the imported hierarchy.
	var to_model := Transform3D()
	var node: Node = _skeleton
	while node != _model:
		to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	_to_skeleton = to_model.basis.orthonormalized().inverse()

	for key: StringName in [&"spinebase", &"chest", &"neck", &"head_", &"jaw",
			&"Arm.L", &"Forearm.L", &"Arm.R", &"Forearm.R",
			&"leg.L", &"sheen.L", &"leg.R", &"sheen.R"]:
		_bones[key] = _find_bone(key)
		if _bones[key] >= 0:
			_driven.append(_bones[key])

	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip := _anim.get_animation_list()[0]
	_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play(clip)
	_anim.seek(_rng.randf() * _anim.current_animation_length, true)


func _process(delta: float) -> void:
	_time += delta
	# The clip rewrites only the bones it animates, so start the driven bones
	# from rest every frame; otherwise the offsets below would pile up.
	for bone in _driven:
		_skeleton.reset_bone_pose(bone)
	_anim.advance(delta * idle_speed)
	_update_gait(delta)
	_update_twitch(delta)
	_apply_pose()


## World position of the mouth (the cutscene aims the camera and blood here).
func get_mouth_position() -> Vector3:
	return _bone_world(_bones[&"jaw"])


func get_head_position() -> Vector3:
	return _bone_world(_bones[&"head_"])


## A single violent jerk of the head (used on every bite).
func jolt(strength: float = 1.0) -> void:
	_twitch += Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.6, 0.6), -0.3) * strength


# =========================================================================
# Layers
# =========================================================================

func _update_gait(delta: float) -> void:
	var speed := absf(move_speed)
	_gait = lerpf(_gait, clampf(speed / 0.8, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	_gallop = lerpf(_gallop, clampf(inverse_lerp(2.0, 3.2, speed), 0.0, 1.0), 1.0 - exp(-3.0 * delta))
	var stride := lerpf(WALK_STRIDE, GALLOP_STRIDE, _gallop)
	_phase = fposmod(_phase + delta * move_speed / stride * TAU, TAU)
	# Low, heavy bob twice per cycle (once per cycle when bounding).
	var bob := lerpf(sin(_phase * 2.0) * 0.025, sin(_phase) * 0.07, _gallop) * _gait
	_model.position = _base_position + Vector3(0.0, bob, 0.0)


func _update_twitch(delta: float) -> void:
	_twitch = _twitch.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * delta))
	if not twitching:
		return
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = _rng.randf_range(1.2, 4.5)
		_twitch += Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.5, 0.5),
			_rng.randf_range(-0.25, 0.25)) * (0.5 + listen)


func _apply_pose() -> void:
	var g := _gait
	var p := _phase
	var gallop_flex := sin(p) * 0.18 * _gallop * g # the spine coils and stretches

	# --- Spine: rear up, lunge, flex ---
	_turn(&"spinebase", Vector3.RIGHT, -0.75 * rear + 0.5 * feed + gallop_flex)
	_turn(&"chest", Vector3.RIGHT, -0.2 * rear + 0.06 * lunge + 0.2 * feed - gallop_flex * 0.5)

	# --- Head: keep it level, then look / listen / thrash / twitch ---
	var look := _look_angles()
	var shake := sin(_time * 23.0) * 0.38 + sin(_time * 37.0) * 0.12
	var roll := head_roll + 0.5 * listen + _twitch.x + shake * 0.35 * thrash
	var yaw := look.x + _twitch.y + shake * thrash
	var pitch := look.y + _twitch.z + 0.5 * rear + 0.7 * lunge + 0.3 * feed
	_turn(&"neck", Vector3.RIGHT, pitch * 0.5)
	_turn(&"neck", Vector3.UP, yaw * 0.5)
	_turn(&"head_", Vector3.RIGHT, pitch * 0.5 + 0.15 * listen)
	_turn(&"head_", Vector3.UP, yaw * 0.5)
	_turn(&"head_", Vector3.FORWARD, roll)

	# --- Jaw ---
	_turn(&"jaw", Vector3.RIGHT, 0.55 * jaw_open)
	if jaw_stretch > 0.001:
		_skeleton.set_bone_pose_scale(_bones[&"jaw"], Vector3(1.0 + 0.25 * jaw_stretch,
			1.0 + 0.9 * jaw_stretch, 1.0 + 0.25 * jaw_stretch))

	# --- Limbs: trot (diagonal pairs) blending into a bound (pairs together) ---
	var arm_l := p
	var arm_r := p + PI * (1.0 - _gallop)
	var leg_l := p + PI
	var leg_r := p + PI * _gallop
	var reach := 1.0 + 0.6 * _gallop # longer strides when charging
	_limb(&"Arm.L", &"Forearm.L", arm_l, 0.32 * reach, 0.35, g)
	_limb(&"Arm.R", &"Forearm.R", arm_r, 0.32 * reach, 0.35, g)
	_limb(&"leg.L", &"sheen.L", leg_l, 0.3 * reach, -0.3, g) # knees fold the other way
	_limb(&"leg.R", &"sheen.R", leg_r, 0.3 * reach, -0.3, g)
	# Feeding: the elbows splay so the chest can sink without the hands sinking.
	if feed > 0.001:
		for side: String in ["L", "R"]:
			var out := 1.0 if side == "L" else -1.0 # the model's left is +X
			_turn(StringName("Arm." + side), Vector3.RIGHT, FEED_ARM.x * feed)
			_turn(StringName("Arm." + side), Vector3.BACK, FEED_ARM.y * out * feed)
			_turn(StringName("Forearm." + side), Vector3.RIGHT, FEED_ARM.z * feed)
	# Reared up: the arms come off the floor and reach forward.
	if rear > 0.001:
		for side: String in ["L", "R"]:
			_turn(StringName("Arm." + side), Vector3.RIGHT, -0.25 * rear)
			_turn(StringName("Forearm." + side), Vector3.RIGHT, -0.45 * rear)


## One leg or arm: swing forward/back around the hip or shoulder and fold the
## lower half while the foot is in the air.
func _limb(upper: StringName, lower: StringName, phase: float, swing: float, fold: float, amount: float) -> void:
	if amount < 0.001:
		return
	var direction := signf(move_speed) if move_speed != 0.0 else 1.0
	var forward := sin(phase) # +1 = reached forward
	var lift := maxf(0.0, cos(phase) * direction) # in the air while it swings forward
	_turn(upper, Vector3.RIGHT, -(forward * swing + lift * 0.15 * signf(fold)) * amount)
	_turn(lower, Vector3.RIGHT, -lift * fold * amount)


## Yaw / pitch (radians, rig space) that turn the head to look_target.
func _look_angles() -> Vector2:
	if look_weight <= 0.001:
		return Vector2.ZERO
	var head := to_local(get_head_position())
	var to := to_local(look_target) - head
	var flat := Vector2(to.x, to.z).length()
	var yaw := clampf(atan2(to.x, to.z), -1.3, 1.3)
	var pitch := clampf(-atan2(to.y, flat), -1.0, 1.0) # +pitch tips the head down
	return Vector2(yaw, pitch) * look_weight


# =========================================================================
# Bone helpers
# =========================================================================

## Rotates a bone around an axis given in rig space, on top of its pose.
func _turn(key: StringName, axis: Vector3, angle: float) -> void:
	var bone: int = _bones.get(key, -1)
	if bone < 0 or absf(angle) < 0.0001:
		return
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := Basis()
	if parent >= 0:
		parent_basis = _skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	var local_axis := (parent_basis.inverse() * (_to_skeleton * axis)).normalized()
	_skeleton.set_bone_pose_rotation(bone,
		(Quaternion(local_axis, angle) * _skeleton.get_bone_pose_rotation(bone)).normalized())


func _bone_world(bone: int) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


func _find_bone(prefix: String) -> int:
	for i in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(i).begins_with(prefix):
			return i
	push_warning("StalkerRig: no bone starting with '%s'" % prefix)
	return -1
