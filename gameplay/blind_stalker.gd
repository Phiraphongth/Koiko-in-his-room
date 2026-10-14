class_name BlindStalker
extends CharacterBody3D
## The Blind Stalker (Level 2). A pale, grinning thing that crawls on all fours
## (body: StalkerRig, the "Smily horror monster" model). It hunts purely by sound:
##  - every EventBus.noise_emitted within `loudness * hearing_multiplier` m
##  - the player's heartbeat, audible within a radius that grows with BPM
##    (holding your breath inside a hiding spot makes you silent)
## States: DORMANT -> PATROL <-> INVESTIGATE / HUNT -> SEARCH, CHECK_HIDING.
## While it listens outside a locker the player has to mash [Q] to keep their
## breath in; if they stop, it drags them out.
## Losing a hidden player -> LOOK_AROUND: it stops, looks around for a moment,
## then walks off to a far patrol point and leaves that locker alone for a while.
## It never sees: a silent player standing still right in front of it is safe.

signal player_caught
signal state_changed(new_state: State)

enum State { DORMANT, PATROL, INVESTIGATE, HUNT, SEARCH, CHECK_HIDING, LOOK_AROUND, FEEDING }

## LOOK_AROUND head turns, in radians off the way it was facing: left, right, back.
const LOOK_SWEEP := [-1.1, 1.1, 0.0]
## Seconds pressed on the spot before it counts as arrived (see _arrived).
const STALL_TIME := 1.0
## Seconds without real progress along a path before it asks for a new one
## (see _watch_progress).
const PROGRESS_CHECK := 1.5

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
@export var check_reach := 2.5 ## listens at a locker door from no farther than this
@export var look_time := 3.2 ## stands and looks around after losing a hidden player
@export var leave_distance := 12.0 ## then walks off to a patrol point at least this far
@export var give_up_time := 12.0 ## ignores the heartbeat from a locker it gave up on
@export var screech_cooldown := 8.0

var state: State = State.DORMANT
var speed_multiplier := 1.0
var patrol_points: Array[Vector3] = []
## The body. The kill cutscene (StalkerKillCutscene) poses it directly.
var rig: StalkerRig

var _player: Player
var _agent: NavigationAgent3D
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
var _stalled_for := 0.0
var _progress_from := Vector3.ZERO
var _progress_time := 0.0
var _unstick_tries := 0
var _given_up_spot: Node3D
var _given_up_until := -100.0
var _look_yaw := 0.0
var _lost_at := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	add_to_group(&"enemy")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45 # low and wide: it crawls
	capsule.height = 1.4
	shape.shape = capsule
	shape.position = Vector3(0, 0.7, 0)
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


## Let it out of the cage.
func release() -> void:
	_growl.play()
	_snap_to_navigation()
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
	if not loud and _gave_up_on_player():
		return # it already listened at that locker and heard nothing
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
		_player.begin_hide_check() # mash [Q] from here on, or it hears the breath go
		return
	if state != State.HUNT:
		_screech()
	_go(pos, State.HUNT)


## A quiet heartbeat from the locker it just gave up on is not worth a second look.
func _gave_up_on_player() -> bool:
	return _player != null and _player.is_hidden and _player.current_hide_spot == _given_up_spot \
		and _now() < _given_up_until


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
				if _player and _player.is_hidden:
					_look_around() # the trail went cold at a hiding spot
				else:
					_begin_search()
		State.SEARCH:
			if _state_time > search_pause:
				_continue_search()
		State.CHECK_HIDING:
			_check_hiding()
		State.LOOK_AROUND:
			_update_look_around(delta)
	_move(delta)
	_check_catch()


func _on_reached_noise() -> void:
	# A thrown bottle frees itself the moment it shatters, so the instance has
	# to be checked before its type — `is` on a freed object is an error.
	if is_instance_valid(_target_source) and _target_source is Throwable \
			and (_target_source as Throwable).is_ringing:
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
	if _flat_distance(_agent.target_position) > check_reach:
		# Stuck on a ledge it cannot climb, nowhere near the door: it never
		# gets to listen, so it gives up on this locker instead of waiting forever.
		_give_up_on_check_spot()
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
	# The player keeps their breath in only by mashing [Q]; the moment the meter
	# runs dry it hears them (a short grace once it gets here).
	if _player.hold_meter <= 0.0 and listening > 0.5:
		_catch()
	elif listening > check_time:
		_give_up_on_check_spot()


func _give_up_on_check_spot() -> void:
	_given_up_spot = _check_spot
	_given_up_until = _now() + give_up_time
	_check_spot = null
	_look_around()


## It lost the player: it stops dead and turns its head left and right for a
## moment, as if it could see, before giving up and walking away.
func _look_around() -> void:
	_lost_at = global_position
	_look_yaw = rotation.y
	_set_state(State.LOOK_AROUND)


func _update_look_around(delta: float) -> void:
	if _state_time > look_time:
		_walk_away()
		return
	# A quick turn, then a still beat holding it, for each head turn.
	var turn := mini(int(_state_time / look_time * LOOK_SWEEP.size()), LOOK_SWEEP.size() - 1)
	rotation.y = lerp_angle(rotation.y, _look_yaw + float(LOOK_SWEEP[turn]), 1.0 - exp(-7.0 * delta))


## Off to a patrol point well away from where it lost the player, rather than
## circling the same lockers.
func _walk_away() -> void:
	var far: Array[Vector3] = []
	for point in patrol_points:
		if point.distance_to(_lost_at) >= leave_distance:
			far.append(point)
	if far.is_empty():
		_set_state(State.PATROL)
		_pick_patrol_point()
	else:
		_go(far[_rng.randi_range(0, far.size() - 1)], State.PATROL)


func _check_catch() -> void:
	if _player == null or _player.is_hidden or _player.state == Player.State.DISABLED:
		return
	if global_position.distance_to(_player.global_position) < catch_distance and state == State.HUNT:
		_catch()


func _catch() -> void:
	_set_state(State.FEEDING)
	velocity = Vector3.ZERO
	_face(_player.global_position)
	player_caught.emit() # the level directs the death cutscene from here


## Stops it in its tracks for the death cutscene, which takes over the body.
func prepare_for_kill() -> void:
	_set_state(State.FEEDING)
	velocity = Vector3.ZERO
	_steps.stop()
	_growl.stop()
	rig.move_speed = 0.0
	rig.listen = 0.0
	rig.twitching = false


## One-shot sound from its body (cutscene choreography).
func make_sound(id: StringName, volume_db: float = 0.0) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(id)
	sound.volume_db = volume_db
	sound.unit_size = 6.0
	sound.max_distance = 40.0
	sound.position = Vector3(0, 1.0, 0.6)
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func screech() -> void:
	_screech(true)


func growl(on: bool) -> void:
	if on:
		_growl.play()
	else:
		_growl.stop()


## Shortest-path yaw that faces `point`, for tweening rotation.y (cutscenes).
func yaw_towards(point: Vector3) -> float:
	var to := point - global_position
	return rotation.y + wrapf(atan2(to.x, to.z) - rotation.y, -PI, PI)


func _pick_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	# Never the point it is already heading for: re-sending the same target
	# does not make the agent ask for a new path, so a lost path stayed lost.
	var choices: Array[Vector3] = []
	for point in patrol_points:
		if point.distance_to(_agent.target_position) > 1.0:
			choices.append(point)
	if choices.is_empty():
		choices = patrol_points.duplicate()
	var best := choices[_rng.randi_range(0, choices.size() - 1)]
	# Prefer points that are not right next to us.
	for attempt in 3:
		if best.distance_to(global_position) > 6.0:
			break
		best = choices[_rng.randi_range(0, choices.size() - 1)]
	_go(best, State.PATROL)


# =========================================================================
# Body
# =========================================================================

func _move(delta: float) -> void:
	var speed := _speed_for_state() * speed_multiplier
	var desired := Vector3.ZERO
	var standing := state == State.SEARCH or state == State.LOOK_AROUND \
		or (state == State.CHECK_HIDING and _arrived())
	var pathing := not standing and not _agent.is_navigation_finished()
	if pathing:
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
	# A path up a ledge it cannot climb (the flooded bay catwalk) leaves it
	# pressed on the spot with the navigation never finishing.
	if pathing:
		_stalled_for = _stalled_for + delta if moving < 0.15 else 0.0
	_watch_progress(delta, pathing)
	if moving > 0.2 and state != State.LOOK_AROUND: # it turns its own head there
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-8.0 * delta))
	# Creeps on all fours, bounds when it charges; freezes and cocks its head
	# whenever it stops to listen.
	rig.move_speed = moving if moving > 0.15 else 0.0
	var listening := moving < 0.3 and (state == State.SEARCH or state == State.CHECK_HIDING)
	rig.listen = move_toward(rig.listen, 1.0 if listening else 0.0, delta * 2.0)
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
	_stalled_for = 0.0
	_set_state(new_state)


## Also true once it has been stuck for a moment: as close as it can get.
func _arrived() -> bool:
	return _agent.is_navigation_finished() or global_position.distance_to(_agent.target_position) < 1.1 \
		or _stalled_for > STALL_TIME


## Watchdog: if it has a path to follow but has not really moved for a while
## (path came back empty, or it ended up just off the navigation mesh, which
## happened when Level 2 was replayed after a death), put it back on the mesh
## and ask for the path again; then try somewhere else.
func _watch_progress(delta: float, pathing: bool) -> void:
	if not pathing:
		_progress_time = 0.0
		_progress_from = global_position
		return
	_progress_time += delta
	if _progress_time < PROGRESS_CHECK:
		return
	var moved := _flat_distance(_progress_from)
	_progress_time = 0.0
	_progress_from = global_position
	if moved > 0.4:
		_unstick_tries = 0
		return
	_unstick_tries += 1
	_snap_to_navigation()
	# A (tiny) change of target is what makes the agent query a fresh path.
	_agent.target_position = _agent.target_position + Vector3(0.01 * (_unstick_tries % 2 * 2 - 1), 0.0, 0.0)
	if _unstick_tries >= 2 and state == State.PATROL:
		_unstick_tries = 0
		_pick_patrol_point()


## Back onto the navigation mesh if it is standing off it.
func _snap_to_navigation() -> void:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return # the map has not been built yet
	var on_mesh := NavigationServer3D.map_get_closest_point(map, global_position)
	if _flat_distance(on_mesh) > 0.25 and _flat_distance(on_mesh) < 3.0:
		global_position = Vector3(on_mesh.x, global_position.y, on_mesh.z)


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _set_state(new_state: State) -> void:
	_state_time = 0.0
	if new_state != state:
		if state == State.CHECK_HIDING and _player:
			_player.end_hide_check() # walked off, gave up or caught them
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


func _make_audio(id: StringName, volume_db: float, unit_size: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.stream = ProceduralAudio.get_stream(id)
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.max_distance = 40.0
	player.position = Vector3(0, 1.1, 0.4)
	add_child(player)
	return player


func _build_body() -> void:
	rig = StalkerRig.new()
	rig.name = "Body"
	add_child(rig)
