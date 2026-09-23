class_name BlindStalker
extends CharacterBody3D
## The Blind Stalker (Level 2). Tall, pale, eyeless. It hunts purely by sound:
##  - every EventBus.noise_emitted within `loudness * hearing_multiplier` m
##  - the player's heartbeat, audible within a radius that grows with BPM
##    (holding your breath inside a hiding spot makes you silent)
## States: DORMANT -> PATROL <-> INVESTIGATE / HUNT -> SEARCH, CHECK_HIDING.
## It never sees: a silent player standing still right in front of it is safe.

signal player_caught
signal state_changed(new_state: State)

enum State { DORMANT, PATROL, INVESTIGATE, HUNT, SEARCH, CHECK_HIDING, FEEDING }

const MODEL := preload("res://Simple_Character_PSX/model/glb/simple-character-psx.glb")
const ANIMATIONS := preload("res://player/animations/player_animations.res")
const BODY_SCALE := Vector3(0.8, 1.25, 0.85) # too tall, too thin
const CREEP_STRIDE := 0.9 * 1.25 # crouch_walk stride scaled by body height
const RUN_STRIDE := 3.24 * 1.25

@export var patrol_speed := 1.2
@export var investigate_speed := 2.2
@export var hunt_speed := 3.7
@export var hearing_multiplier := 1.0
@export var heartbeat_base_radius := 2.5
@export var heartbeat_max_radius := 11.0
@export var catch_distance := 1.3
@export var threat_radius := 14.0
@export var search_pause := 2.5
@export var check_time := 3.5
@export var screech_cooldown := 8.0

var state: State = State.DORMANT
var speed_multiplier := 1.0
var patrol_points: Array[Vector3] = []

var _player: Player
var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _growl: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _steps: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _state_time := 0.0
var _heard_player_at := -100.0
var _last_screech := -100.0
var _heartbeat_timer := 0.0
var _search_left := 0
var _step_accum := 0.0
var _target_source: Node
var _check_spot: Node3D
var _check_arrived_at := -1.0
var _current_anim: StringName = &""


func _ready() -> void:
	_rng.randomize()
	add_to_group(&"enemy")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 2.2
	shape.shape = capsule
	shape.position = Vector3(0, 1.1, 0)
	add_child(shape)
	_build_body()
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.7
	_agent.target_desired_distance = 1.0
	_agent.path_max_distance = 3.0
	add_child(_agent)
	_growl = _make_audio(&"growl", -6.0, 3.0)
	_voice = _make_audio(&"screech", 2.0, 8.0)
	_steps = _make_audio(&"thud", -4.0, 4.0)
	EventBus.noise_emitted.connect(_on_noise)
	_play_anim(&"crouch_idle", 0.5)


## Let it out of the cage.
func release() -> void:
	_growl.play()
	_set_state(State.PATROL)
	_pick_patrol_point()


func enrage(multiplier: float) -> void:
	speed_multiplier = maxf(speed_multiplier, multiplier)
	hearing_multiplier = maxf(hearing_multiplier, multiplier)


## Something very loud it cannot ignore (the escape alarm).
func summon(target: Vector3) -> void:
	_target_source = null
	_go(target, State.HUNT)
	_screech()


# =========================================================================
# Senses
# =========================================================================

func _on_noise(pos: Vector3, loudness: float, source: Node) -> void:
	if state == State.DORMANT or state == State.FEEDING:
		return
	if global_position.distance_to(pos) > loudness * hearing_multiplier:
		return
	if source is Player:
		_hear_player(pos, true)
		return
	# A decoy. Ignore it only if we are chasing the player right now and they are closer.
	var chasing := state == State.HUNT and _now() - _heard_player_at < 1.5
	if chasing and _player and global_position.distance_to(_player.global_position) < global_position.distance_to(pos):
		return
	_target_source = source
	_search_left = 1
	_go(pos, State.INVESTIGATE)


func _listen_heartbeat(delta: float) -> void:
	_heartbeat_timer -= delta
	if _heartbeat_timer > 0.0 or _player == null or _player.state == Player.State.DISABLED:
		return
	_heartbeat_timer = 0.3
	var radius := lerpf(heartbeat_base_radius, heartbeat_max_radius, _player.get_heartbeat_normalized()) * hearing_multiplier
	if _player.is_hidden:
		radius *= 0.0 if _player.is_holding_breath else 0.5
	elif _player.is_holding_breath:
		radius *= 0.3
	if global_position.distance_to(_player.global_position) <= radius:
		_hear_player(_player.global_position, false)


## `loud`: an actual noise (gasp, collar) rather than a heartbeat.
func _hear_player(pos: Vector3, loud: bool) -> void:
	_heard_player_at = _now()
	_target_source = null
	if _player and _player.is_hidden and _player.current_hide_spot:
		if state == State.CHECK_HIDING and _check_spot == _player.current_hide_spot:
			if loud and _check_arrived_at >= 0.0:
				_catch() # a gasp right next to it
			return # already listening at this locker
		_check_spot = _player.current_hide_spot
		_check_arrived_at = -1.0
		var front := _check_spot.global_position + _check_spot.global_basis.z * 1.0
		_go(front, State.CHECK_HIDING)
		return
	if state != State.HUNT:
		_screech()
	_go(pos, State.HUNT)


## Heartbeat rises the closer it is (the player "feels" it before seeing it).
func _threaten_player() -> void:
	if _player == null:
		return
	var closeness := clampf(1.0 - global_position.distance_to(_player.global_position) / threat_radius, 0.0, 1.0)
	_player.report_threat(closeness * (1.0 if state == State.HUNT else 0.75))


# =========================================================================
# Brain
# =========================================================================

func _physics_process(delta: float) -> void:
	if state == State.DORMANT or state == State.FEEDING:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Player
	_state_time += delta
	_listen_heartbeat(delta)
	_threaten_player()
	match state:
		State.PATROL:
			if _arrived():
				_pick_patrol_point()
		State.INVESTIGATE:
			if _arrived():
				_on_reached_noise()
		State.HUNT:
			if _arrived() and _now() - _heard_player_at > 1.0:
				_begin_search()
		State.SEARCH:
			if _state_time > search_pause:
				_continue_search()
		State.CHECK_HIDING:
			_check_hiding()
	_move(delta)
	_check_catch()


func _on_reached_noise() -> void:
	if _target_source is Throwable and is_instance_valid(_target_source) and (_target_source as Throwable).is_ringing:
		(_target_source as Throwable).silence() # smashes the ringing clock
		_steps.stream = ProceduralAudio.get_stream(&"bang")
		_steps.play()
	_target_source = null
	_begin_search()


func _begin_search() -> void:
	_set_state(State.SEARCH)


func _continue_search() -> void:
	if _search_left > 0:
		_search_left -= 1
		var offset := Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
		_go(_closest_nav_point(global_position + offset), State.INVESTIGATE)
	else:
		_set_state(State.PATROL)
		_pick_patrol_point()


func _check_hiding() -> void:
	if _check_spot == null or _player == null:
		_set_state(State.SEARCH)
		return
	if not _arrived():
		return
	# Standing right outside the locker, listening.
	if _check_arrived_at < 0.0:
		_check_arrived_at = _now()
	var listening := _now() - _check_arrived_at
	_face(_check_spot.global_position)
	var still_hidden := _player.is_hidden and _player.current_hide_spot == _check_spot
	if not still_hidden:
		_set_state(State.SEARCH)
		return
	var loud_heart := _player.get_heartbeat_normalized() > 0.45 and not _player.is_holding_breath
	if loud_heart and listening > 1.0:
		_catch()
	elif listening > check_time:
		_check_spot = null
		_search_left = 1
		_set_state(State.SEARCH)


func _check_catch() -> void:
	if _player == null or _player.is_hidden or _player.state == Player.State.DISABLED:
		return
	if global_position.distance_to(_player.global_position) < catch_distance and state == State.HUNT:
		_catch()


func _catch() -> void:
	_set_state(State.FEEDING)
	velocity = Vector3.ZERO
	_face(_player.global_position)
	_screech(true)
	_play_anim(&"run", 1.6)
	player_caught.emit()


func _pick_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	var best := patrol_points[_rng.randi_range(0, patrol_points.size() - 1)]
	# Prefer points that are not right next to us.
	for attempt in 3:
		if best.distance_to(global_position) > 6.0:
			break
		best = patrol_points[_rng.randi_range(0, patrol_points.size() - 1)]
	_go(best, State.PATROL)


# =========================================================================
# Body
# =========================================================================

func _move(delta: float) -> void:
	var speed := _speed_for_state() * speed_multiplier
	var desired := Vector3.ZERO
	var standing := state == State.SEARCH or (state == State.CHECK_HIDING and _arrived())
	if not standing and not _agent.is_navigation_finished():
		var to_next := _agent.get_next_path_position() - global_position
		to_next.y = 0.0
		if to_next.length() > 0.05:
			desired = to_next.normalized() * speed
	var weight := 1.0 - exp(-6.0 * delta)
	velocity.x = lerpf(velocity.x, desired.x, weight)
	velocity.z = lerpf(velocity.z, desired.z, weight)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	var horizontal := Vector2(velocity.x, velocity.z)
	var moving := horizontal.length()
	if moving > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-8.0 * delta))
	# Hunched and creeping while it listens; it only straightens up to charge.
	if moving > 2.8:
		_play_anim(&"run", moving / RUN_STRIDE)
	elif moving > 0.2:
		_play_anim(&"crouch_walk", moving / CREEP_STRIDE)
	else:
		_play_anim(&"crouch_idle", 0.8)
	_step_accum += moving * delta
	if _step_accum > (1.9 if moving > 2.8 else 0.85):
		_step_accum = 0.0
		_steps.stream = ProceduralAudio.get_stream(&"thud")
		_steps.volume_db = -8.0 + moving * 2.0
		_steps.play()


func _speed_for_state() -> float:
	match state:
		State.PATROL:
			return patrol_speed
		State.HUNT:
			return hunt_speed
	return investigate_speed


func _go(target: Vector3, new_state: State) -> void:
	_agent.target_position = target
	_set_state(new_state)


func _arrived() -> bool:
	return _agent.is_navigation_finished() or global_position.distance_to(_agent.target_position) < 1.1


func _set_state(new_state: State) -> void:
	_state_time = 0.0
	if new_state != state:
		state = new_state
		state_changed.emit(new_state)


func _face(target: Vector3) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(to.x, to.z)


func _screech(force: bool = false) -> void:
	if force or _now() - _last_screech > screech_cooldown:
		_last_screech = _now()
		_voice.play()
		if _player:
			_player.add_heartbeat_spike(25.0)


func _closest_nav_point(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _play_anim(anim_name: StringName, speed: float) -> void:
	if anim_name != _current_anim:
		_current_anim = anim_name
		_anim.play(anim_name, 0.3)
	_anim.speed_scale = speed


func _make_audio(id: StringName, volume_db: float, unit_size: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.stream = ProceduralAudio.get_stream(id)
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.max_distance = 40.0
	player.position = Vector3(0, 2.0, 0)
	add_child(player)
	return player


## Pale, too tall, too thin, and no face: the character model with the head
## replaced by a smooth eyeless skull with a dark mouth slit.
func _build_body() -> void:
	var model := MODEL.instantiate() as Node3D
	model.scale = BODY_SCALE
	add_child(model)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.5, 0.48, 0.44)
	skin.roughness = 0.55 # clammy
	skin.rim_enabled = true
	skin.rim = 0.4
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = skin
		if mesh.name == "head":
			(mesh as MeshInstance3D).visible = false
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var attach := BoneAttachment3D.new()
	attach.bone_name = "spine.005"
	skeleton.add_child(attach)
	var skull := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	skull.mesh = sphere
	skull.material_override = skin
	skull.scale = Vector3(0.95, 1.55, 1.15) # in skeleton units (1 unit ≈ 12 cm)
	skull.position = Vector3(0, 0.8, 0.1)
	attach.add_child(skull)
	var mouth := MeshInstance3D.new()
	var slit := BoxMesh.new()
	slit.size = Vector3(0.9, 0.12, 0.1)
	mouth.mesh = slit
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.0, 0.0)
	mouth.material_override = dark
	mouth.position = Vector3(0, 0.2, 1.15)
	attach.add_child(mouth)
	_anim = AnimationPlayer.new()
	model.add_child(_anim)
	_anim.add_animation_library(&"", ANIMATIONS)
