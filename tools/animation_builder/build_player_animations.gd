extends Node
## Offline tool: procedurally bakes the player's AnimationLibrary for the
## simple_character rig (Rigify-style bone names, T-pose rest).
##
## Legs are driven by foot trajectories + analytic two-bone IK, so planted
## feet never slide. Walk/run/crouch_walk are baked as 1-second normalized
## cycles (phase 0..1) so they phase-sync when blended; PlayerAnimator
## time-scales them by actual speed / stride length.
##
## Reference numbers (gait biomechanics):
##  - Walk: stance ~60% of cycle, pelvis rotation ~±4°, pelvic list ~±3°,
##    vertical COM excursion ~4-5 cm, arm swing out of phase with legs,
##    thorax counter-rotates against pelvis.
##  - Run: stance <40% of cycle (flight phase), knee flexes ~40-50° in stance
##    and up to ~100-125° in mid-swing (heel recovery), COM lowest at mid-stance.
##
## Run: open build_player_animations.tscn and press F6, or
##   godot --headless --path . res://tools/animation_builder/build_player_animations.tscn

const MODEL_PATH := "res://Simple_Character_PSX/model/glb/simple-character-psx.glb"
const OUTPUT_PATH := "res://player/animations/player_animations.res"
const TRACK_PREFIX := "simple_character/Skeleton3D:"
const FPS := 30.0

const X := Vector3.RIGHT # model: +X = character's left, +Y up, +Z forward
const Y := Vector3.UP
const Z := Vector3.BACK

# Normalized-cycle gaits. Distances in meters, angles in degrees.
# stride = hip travel per cycle; front = ankle ahead of hip at foot contact.
const WALK := {
	"stride": 1.44, "duty": 0.60, "front": 0.36, "width": 0.0, "hip_z": 0.0,
	"drop": 0.045, "bob": 0.022, "sway": 0.025, "pelvis_yaw": 4.0, "pelvis_roll": 3.0,
	"lean": 4.0, "thorax_yaw": 3.0, "head_bob": 1.0,
	"heel": 15.0, "hs_end": 0.15, "heel_off": 0.55, "toe_off": 40.0, "swing_pitch": -3.0,
	"lift": 0.06, "lift_skew": 0.85,
	"arm_down": 78.0, "arm_flex": 2.0, "arm_swing": 14.0, "elbow": 15.0, "elbow_swing": 18.0,
	"arm_lag": 0.05, "curl": 0.35,
}
const RUN := {
	"stride": 3.24, "duty": 0.28, "front": 0.33, "width": -0.02, "hip_z": 0.0,
	"drop": 0.06, "bob": -0.025, "sway": 0.015, "pelvis_yaw": 8.0, "pelvis_roll": 4.0,
	"lean": 12.0, "thorax_yaw": 8.0, "head_bob": 2.0,
	"heel": 3.0, "hs_end": 0.1, "heel_off": 0.35, "toe_off": 45.0, "swing_pitch": 25.0,
	"lift": 0.38, "lift_skew": 0.55,
	"arm_down": 74.0, "arm_flex": 4.0, "arm_swing": 28.0, "elbow": 80.0, "elbow_swing": 20.0,
	"arm_lag": 0.03, "curl": 0.8,
}
const CROUCH_WALK := {
	"stride": 0.9, "duty": 0.65, "front": 0.28, "width": 0.02, "hip_z": -0.06,
	"drop": 0.42, "bob": 0.012, "sway": 0.03, "pelvis_yaw": 6.0, "pelvis_roll": 2.0,
	"lean": 45.0, "thorax_yaw": 3.0, "head_bob": 0.5,
	"heel": 10.0, "hs_end": 0.15, "heel_off": 0.6, "toe_off": 25.0, "swing_pitch": -5.0,
	"lift": 0.08, "lift_skew": 0.8,
	"arm_down": 74.0, "arm_flex": 10.0, "arm_swing": 9.0, "elbow": 32.0, "elbow_swing": 12.0,
	"arm_lag": 0.05, "curl": 0.5,
}

# Standing poses (feet planted). breaths = breath cycles per loop.
const IDLE := {
	"drop": 0.015, "hip_z": 0.0, "width": 0.0, "l_z": 0.04, "r_z": -0.03, "lean": 2.0,
	"breaths": 1.0, "breath_deg": 1.5, "shrug": 0.0, "breath_shrug": 1.2, "sway": 0.012,
	"arm_down": 80.0, "arm_flex": 3.0, "elbow": 12.0, "curl": 0.35, "head_pitch": 0.0, "look": 2.0,
}
const IDLE_TENSE := {
	"drop": 0.07, "hip_z": -0.02, "width": 0.05, "l_z": 0.1, "r_z": -0.1, "lean": 10.0,
	"breaths": 2.0, "breath_deg": 3.0, "shrug": 5.0, "breath_shrug": 2.0, "sway": 0.008,
	"arm_down": 77.0, "arm_flex": 6.0, "elbow": 28.0, "curl": 0.75, "head_pitch": 3.0, "look": 6.0,
}
const EXHAUSTED := {
	"drop": 0.10, "hip_z": -0.06, "width": 0.05, "l_z": 0.05, "r_z": -0.05, "lean": 42.0,
	"breaths": 3.0, "breath_deg": 5.0, "shrug": 2.0, "breath_shrug": 4.0, "sway": 0.005,
	"arm_down": 85.0, "arm_flex": 8.0, "elbow": 10.0, "curl": 0.3, "head_pitch": -8.0, "look": 1.0,
}
const CROUCH_IDLE := {
	"drop": 0.44, "hip_z": -0.08, "width": 0.03, "l_z": 0.14, "r_z": -0.12, "lean": 45.0,
	"breaths": 1.0, "breath_deg": 2.0, "shrug": 2.0, "breath_shrug": 1.5, "sway": 0.008,
	"arm_down": 74.0, "arm_flex": 12.0, "elbow": 35.0, "curl": 0.55, "head_pitch": 0.0, "look": 4.0,
}

var _sk: Skeleton3D
var _u := 1.0 # skeleton units per meter
var _parent := PackedInt32Array()
var _rest_g: Array[Transform3D] = []
var _rest_l: Array[Transform3D] = []
var _rest_gq: Array[Quaternion] = []
var _bones: Dictionary[String, int] = {}
var _root := 0
var _ankle_rest := Vector3.ZERO  # meters, left foot
var _toe_off := Vector3.ZERO     # ankle -> ball of foot (meters, yz only)
var _heel_off := Vector3.ZERO    # ankle -> heel (meters, yz only)


class Pose:
	var rot: Array[Quaternion] = []
	var root_offset := Vector3.ZERO

	func _init(count: int) -> void:
		rot.resize(count)
		rot.fill(Quaternion.IDENTITY)


func _ready() -> void:
	var model: Node3D = load(MODEL_PATH).instantiate()
	add_child(model)
	_sk = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_u = 1.0 / (_sk.get_parent() as Node3D).scale.x
	for i in _sk.get_bone_count():
		_bones[_sk.get_bone_name(i)] = i
		_parent.append(_sk.get_bone_parent(i))
		_rest_g.append(_sk.get_bone_global_rest(i))
		_rest_l.append(_sk.get_bone_rest(i))
		_rest_gq.append(_sk.get_bone_global_rest(i).basis.get_rotation_quaternion())
		if _sk.get_bone_parent(i) == -1:
			_root = i
	_ankle_rest = _pos_m("foot.L")
	_toe_off = _pos_m("toe.L") - _ankle_rest
	_toe_off.x = 0.0
	_heel_off = _pos_m("heel.02.L") - _ankle_rest
	_heel_off.x = 0.0

	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _bake(4.0, true, _stand.bind(IDLE)))
	lib.add_animation(&"idle_tense", _bake(4.0, true, _stand.bind(IDLE_TENSE)))
	lib.add_animation(&"exhausted", _bake(4.0, true, _stand.bind(EXHAUSTED)))
	lib.add_animation(&"crouch_idle", _bake(4.0, true, _stand.bind(CROUCH_IDLE)))
	lib.add_animation(&"walk", _bake(1.0, true, _gait.bind(WALK)))
	lib.add_animation(&"run", _bake(1.0, true, _gait.bind(RUN)))
	lib.add_animation(&"crouch_walk", _bake(1.0, true, _gait.bind(CROUCH_WALK)))
	lib.add_animation(&"jump", _bake(0.6, true, _jump))
	lib.add_animation(&"fall", _bake(0.8, true, _fall))
	lib.add_animation(&"land", _bake(0.5, false, _land))

	DirAccess.make_dir_recursive_absolute(OUTPUT_PATH.get_base_dir())
	var err := ResourceSaver.save(lib, OUTPUT_PATH)
	print("Saved %s (%d animations) -> %s" % [OUTPUT_PATH, lib.get_animation_list().size(), error_string(err)])
	get_tree().quit()


# =========================================================================
# Baking
# =========================================================================

func _bake(length: float, loop: bool, pose_func: Callable) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var count := _sk.get_bone_count()
	var rot_tracks: Array[int] = []
	for b in count:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(TRACK_PREFIX + _sk.get_bone_name(b)))
		rot_tracks.append(track)
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath(TRACK_PREFIX + _sk.get_bone_name(_root)))

	var frames := int(round(length * FPS))
	for i in frames + 1:
		var phase := float(i) / frames
		var time := phase * length
		var pose := Pose.new(count)
		pose_func.call(pose, phase)
		var global_q: Array[Quaternion] = []
		global_q.resize(count)
		for b in count:
			global_q[b] = (_delta(pose, b) * _rest_gq[b]).normalized()
		for b in count:
			var par := _parent[b]
			var local_q := global_q[b] if par == -1 else (global_q[par].inverse() * global_q[b]).normalized()
			anim.rotation_track_insert_key(rot_tracks[b], time, local_q)
		anim.position_track_insert_key(pos_track, time, _rest_l[_root].origin + pose.root_offset)
	return anim


# =========================================================================
# Pose math. Each bone stores a rotation `rot` expressed in the model's
# rest frame; the bone's global delta = parent's global delta * rot.
# =========================================================================

func _delta(p: Pose, b: int) -> Quaternion:
	var q := p.rot[b]
	var par := _parent[b]
	while par != -1:
		q = p.rot[par] * q
		par = _parent[par]
	return q


func _origin(p: Pose, b: int) -> Vector3:
	var par := _parent[b]
	if par == -1:
		return _rest_g[b].origin + p.root_offset
	return _origin(p, par) + _delta(p, par) * (_rest_g[b].origin - _rest_g[par].origin)


func _rot(p: Pose, bone: String, axis: Vector3, degrees: float) -> void:
	var b := _bones[bone]
	p.rot[b] = Quaternion(axis, deg_to_rad(degrees)) * p.rot[b]


func _set_global(p: Pose, b: int, q: Quaternion) -> void:
	var par := _parent[b]
	var parent_delta := _delta(p, par) if par != -1 else Quaternion.IDENTITY
	p.rot[b] = parent_delta.inverse() * q


func _pos_m(bone: String) -> Vector3:
	return _rest_g[_bones[bone]].origin / _u


## Two-bone leg IK toward an ankle target (meters, model space).
func _solve_leg(p: Pose, side: String, ankle_m: Vector3, pitch: float, toe_deg: float, pole: Vector3) -> void:
	var thigh := _bones["thigh." + side]
	var shin := _bones["shin." + side]
	var foot := _bones["foot." + side]
	var hip := _origin(p, thigh)
	var l1 := (_rest_g[shin].origin - _rest_g[thigh].origin).length()
	var l2 := (_rest_g[foot].origin - _rest_g[shin].origin).length()
	var to_target := ankle_m * _u - hip
	var dist := clampf(to_target.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := to_target.normalized()
	var along := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var height := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var knee := hip + dir * along + bend * height
	var ankle := hip + dir * dist
	var rest_thigh := (_rest_g[shin].origin - _rest_g[thigh].origin).normalized()
	var rest_shin := (_rest_g[foot].origin - _rest_g[shin].origin).normalized()
	_set_global(p, thigh, Quaternion(rest_thigh, (knee - hip).normalized()))
	_set_global(p, shin, Quaternion(rest_shin, (ankle - knee).normalized()))
	_set_global(p, foot, Quaternion(X, deg_to_rad(pitch)))
	if toe_deg != 0.0:
		_rot(p, "toe." + side, X, -toe_deg)


## Ankle position for a foot on the ground rolling on heel (pitch < 0,
## toes up) or ball of foot (pitch > 0, heel up). `z` = flat-foot ankle z.
func _foot_contact(x: float, z: float, pitch: float) -> Vector3:
	var flat := Vector3(x, _ankle_rest.y, z)
	if is_zero_approx(pitch):
		return flat
	var pivot := _toe_off if pitch > 0.0 else _heel_off
	return flat + pivot + Basis(X, deg_to_rad(pitch)) * -pivot


func _arm(p: Pose, side: String, down: float, flex: float, elbow: float, curl: float) -> void:
	var s := 1.0 if side == "L" else -1.0
	_rot(p, "upper_arm." + side, Z, -down * s)
	_rot(p, "upper_arm." + side, X, -flex)
	_rot(p, "forearm." + side, Y, -elbow * s)
	for finger in ["f_index", "f_middle", "f_ring", "f_pinky"]:
		_rot(p, "%s.01.%s" % [finger, side], Z, -(10.0 + 30.0 * curl) * s)
		_rot(p, "%s.02.%s" % [finger, side], Z, -(10.0 + 55.0 * curl) * s)
		_rot(p, "%s.03.%s" % [finger, side], Z, -(5.0 + 40.0 * curl) * s)
	_rot(p, "thumb.02." + side, Z, -(5.0 + 20.0 * curl) * s)
	_rot(p, "thumb.03." + side, Z, -(5.0 + 25.0 * curl) * s)


func _torso(p: Pose, lean: float, twist: float, head_twist: float, head_pitch: float, roll_counter: float) -> void:
	_rot(p, "spine.001", Z, roll_counter)
	_rot(p, "spine.001", X, lean * 0.45)
	_rot(p, "spine.002", Y, twist * 0.5)
	_rot(p, "spine.002", X, lean * 0.3)
	_rot(p, "spine.003", Y, twist * 0.5)
	_rot(p, "spine.003", X, lean * 0.25)
	# Keep the eyes level and facing forward.
	_rot(p, "spine.004", Y, head_twist * 0.6)
	_rot(p, "spine.004", X, -lean * 0.5)
	_rot(p, "spine.005", Y, head_twist * 0.4)
	_rot(p, "spine.005", X, -lean * 0.45 + head_pitch)


# =========================================================================
# Poses
# =========================================================================

func _gait(p: Pose, phase: float, g: Dictionary) -> void:
	var duty: float = g.duty
	var z_front: float = g.front
	var z_back: float = z_front - g.stride * duty
	var mid := duty * 0.5

	# Pelvis: vertical bob (2x per cycle), lateral sway, rotation, list.
	var yaw: float = -g.pelvis_yaw * cos(TAU * phase)
	var roll: float = g.pelvis_roll * cos(TAU * (phase - mid))
	var bob_wave := cos(2.0 * TAU * (phase - mid))
	p.root_offset = Vector3(g.sway * cos(TAU * (phase - mid)), -g.drop + g.bob * bob_wave, g.hip_z) * _u
	_rot(p, "spine", Z, roll)
	_rot(p, "spine", Y, yaw)

	for side in ["L", "R"]:
		var sgn := 1.0 if side == "L" else -1.0
		var leg_phase := fposmod(phase - (0.0 if side == "L" else 0.5), 1.0)
		var x: float = (_ankle_rest.x + g.width) * sgn
		var ankle: Vector3
		var pitch := 0.0
		var toe := 0.0
		if leg_phase < duty:
			var s := leg_phase / duty
			if s < g.hs_end:
				pitch = -g.heel * (1.0 - smoothstep(0.0, g.hs_end, s))
			elif s > g.heel_off:
				pitch = g.toe_off * smoothstep(g.heel_off, 1.0, s)
				toe = pitch # toes stay flat while the heel rises
			ankle = _foot_contact(x, lerpf(z_front, z_back, s), pitch)
		else:
			var s := (leg_phase - duty) / (1.0 - duty)
			if s < 0.4:
				pitch = lerpf(g.toe_off, g.swing_pitch, smoothstep(0.0, 0.4, s))
			else:
				pitch = lerpf(g.swing_pitch, -g.heel, smoothstep(0.4, 1.0, s))
			toe = g.toe_off * (1.0 - smoothstep(0.0, 0.3, s))
			var z := lerpf(z_back, z_front, smoothstep(0.0, 1.0, s))
			var lift: float = g.lift * sin(PI * pow(s, g.lift_skew))
			ankle = _foot_contact(x, z, pitch) + Vector3(0.0, lift, 0.0)
		var pole := Quaternion(Y, deg_to_rad(yaw)) * Vector3(0.12 * sgn, 0.0, 1.0).normalized()
		_solve_leg(p, side, ankle, pitch, toe, pole)

	# Thorax counter-rotates against the pelvis; head stays stable.
	var thorax: float = g.thorax_yaw * cos(TAU * phase)
	_torso(p, g.lean, thorax - yaw, -thorax, -g.head_bob * bob_wave, -roll * 0.7)

	# Arms swing opposite to the same-side leg.
	var swing := cos(TAU * (phase - g.arm_lag))
	_arm(p, "L", g.arm_down, g.arm_flex - g.arm_swing * swing, g.elbow + g.elbow_swing * maxf(-swing, 0.0), g.curl)
	_arm(p, "R", g.arm_down, g.arm_flex + g.arm_swing * swing, g.elbow + g.elbow_swing * maxf(swing, 0.0), g.curl)


func _stand(p: Pose, phase: float, g: Dictionary) -> void:
	var breath := 0.5 - 0.5 * cos(TAU * phase * g.breaths) # 0 = exhaled, 1 = inhaled
	var sway: float = g.sway * sin(TAU * phase)
	p.root_offset = Vector3(sway, -g.drop + 0.004 * breath, g.hip_z) * _u
	_rot(p, "spine", Z, sway * 60.0) # weight shift tilts the pelvis slightly
	var x: float = _ankle_rest.x + g.width
	_solve_leg(p, "L", Vector3(x, _ankle_rest.y, g.l_z), 0.0, 0.0, Vector3(0.15, 0.0, 1.0).normalized())
	_solve_leg(p, "R", Vector3(-x, _ankle_rest.y, g.r_z), 0.0, 0.0, Vector3(-0.15, 0.0, 1.0).normalized())

	var look: float = g.look * sin(TAU * phase + 1.3)
	_torso(p, g.lean, 0.0, look, g.head_pitch - g.breath_deg * 0.3 * breath, -sway * 60.0)
	_rot(p, "spine.003", X, -g.breath_deg * breath) # chest rises on inhale
	var shrug: float = g.shrug + g.breath_shrug * breath
	_rot(p, "shoulder.L", Z, shrug)
	_rot(p, "shoulder.R", Z, -shrug)
	_arm(p, "L", g.arm_down, g.arm_flex, g.elbow, g.curl)
	_arm(p, "R", g.arm_down, g.arm_flex, g.elbow, g.curl)


func _jump(p: Pose, phase: float) -> void:
	var w := sin(TAU * phase) * 0.02
	_rot(p, "spine", X, -4.0)
	var x := _ankle_rest.x
	_solve_leg(p, "L", Vector3(x, 0.38 + w, 0.22), -5.0, 0.0, Vector3(0.1, 0, 1).normalized())
	_solve_leg(p, "R", Vector3(-x, 0.22 - w, -0.28), 30.0, 0.0, Vector3(-0.1, 0, 1).normalized())
	_torso(p, 8.0, 0.0, 0.0, 0.0, 0.0)
	_arm(p, "L", 62.0, 22.0 + w * 150.0, 35.0, 0.4)
	_arm(p, "R", 62.0, 8.0 - w * 150.0, 35.0, 0.4)


func _fall(p: Pose, phase: float) -> void:
	var w := sin(TAU * phase)
	var x := _ankle_rest.x + 0.04
	_solve_leg(p, "L", Vector3(x, 0.20 + 0.03 * w, 0.14), 10.0, 0.0, Vector3(0.1, 0, 1).normalized())
	_solve_leg(p, "R", Vector3(-x, 0.14 - 0.03 * w, -0.08), 15.0, 0.0, Vector3(-0.1, 0, 1).normalized())
	_torso(p, -4.0, 3.0 * w, 0.0, 6.0, 0.0)
	_arm(p, "L", 35.0 + 8.0 * w, 5.0 + 8.0 * w, 20.0, 0.3)
	_arm(p, "R", 35.0 - 8.0 * w, 5.0 - 8.0 * w, 20.0, 0.3)


func _land(p: Pose, phase: float) -> void:
	# Fast compression (knees absorb impact) then slower recovery.
	var dip := smoothstep(0.0, 0.2, phase) if phase < 0.2 else 1.0 - smoothstep(0.2, 1.0, phase)
	p.root_offset = Vector3(0.0, -(0.02 + 0.22 * dip), -0.03 * dip) * _u
	var x := _ankle_rest.x + 0.03
	_solve_leg(p, "L", Vector3(x, _ankle_rest.y, 0.08), 0.0, 0.0, Vector3(0.15, 0, 1).normalized())
	_solve_leg(p, "R", Vector3(-x, _ankle_rest.y, -0.06), 0.0, 0.0, Vector3(-0.15, 0, 1).normalized())
	_torso(p, 4.0 + 18.0 * dip, 0.0, 0.0, 0.0, 0.0)
	_arm(p, "L", 76.0 - 14.0 * dip, 4.0 + 14.0 * dip, 15.0 + 20.0 * dip, 0.5)
	_arm(p, "R", 76.0 - 14.0 * dip, 4.0 + 14.0 * dip, 15.0 + 20.0 * dip, 0.5)
