class_name Player
extends CharacterBody3D
## Third-person player controller for "Kopiko in his room".
##
## Handles movement (walk / run / crouch / jump), camera look, stamina,
## heartbeat, breath-holding, noise emission, interaction and hiding.
## Animation is handled by the PlayerAnimator child, which only reads state.
## Level-specific abilities (climbing, wall-run, swinging, throwing) will be
## added later as separate child components that use the public API below.
## Everything the outside world needs to know is sent through EventBus.

signal state_changed(new_state: State, old_state: State)
signal footstep(loudness: float)
signal gasped

enum State { IDLE, WALK, RUN, CROUCH, AIRBORNE, HIDDEN, CLIMB, SWING, DISABLED }

@export_group("Movement") ## defaults match real human gait speeds
@export var walk_speed := 1.6
@export var run_speed := 4.5
@export var crouch_speed := 1.0
@export var acceleration := 8.0
@export_range(0.0, 1.0) var air_control := 0.3
@export var jump_velocity := 4.5
@export var turn_speed := 8.0

@export_group("Body") ## measured from the model's animations
@export var stand_height := 2.0
@export var crouch_height := 1.5

@export_group("Camera")
@export var mouse_sensitivity := 0.003
@export var pitch_min_deg := -70.0
@export var pitch_max_deg := 50.0
@export var sprint_fov_boost := 6.0
@export var land_camera_dip := 0.012 ## meters of camera dip per m/s of fall speed

@export_group("Stamina")
@export var max_stamina := 100.0
@export var stamina_drain_rate := 20.0 ## per second while running
@export var stamina_regen_rate := 15.0
@export var stamina_regen_delay := 1.0
@export var min_stamina_to_run := 20.0 ## needed to sprint again after exhaustion

@export_group("Heartbeat")
@export var resting_bpm := 70.0
@export var max_bpm := 180.0
@export var critical_bpm := 140.0
@export var critical_hysteresis := 10.0
@export var bpm_rise_rate := 25.0
@export var bpm_fall_rate := 8.0
@export var calm_bpm_rate := 30.0 ## extra fall speed while calming down
@export var run_bpm_bonus := 35.0
@export var threat_bpm_bonus := 90.0 ## added at threat level 1.0
@export var spike_decay_rate := 10.0

@export_group("Breath")
@export var max_breath := 8.0 ## seconds of breath-holding
@export var breath_regen_rate := 1.0
@export var gasp_noise := 10.0
@export var gasp_bpm_spike := 25.0

@export_group("Noise") ## values are hearing radii in meters
@export var walk_step_length := 0.72 ## half of the animation stride
@export var run_step_length := 1.62
@export var crouch_step_length := 0.45
@export var crouch_noise := 1.0
@export var walk_noise := 4.0
@export var run_noise := 14.0
@export var jump_noise := 3.0
@export var land_noise := 8.0

@export_group("Wall run") ## Level 3 parkour
@export var wall_run_enabled := false
@export var wall_run_time := 1.4
@export var wall_run_speed := 5.0
@export var wall_run_gravity := 0.18 ## fraction of normal gravity while on the wall
@export var wall_run_min_speed := 2.5

@export_group("Interaction")
@export var interact_range := 2.5

var state: State = State.IDLE
var stamina := 0.0
var breath := 0.0
var heartbeat_bpm := 0.0
var is_crouching := false
var is_holding_breath := false
var is_exhausted := false
var is_hidden: bool:
	get:
		return state == State.HIDDEN
## Loudest active surface (1 = normal floor, >1 = water / metal).
var surface_noise_multiplier: float:
	get:
		return _surface_noise_mult
## Where the player is hiding (HidePoint of a HideSpot), or null.
var current_hide_spot: Node3D

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = _collision.shape as CapsuleShape3D
@onready var _visual: Node3D = $Visual
@onready var _camera_yaw: Node3D = $CameraYaw
@onready var _camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var _camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D
@onready var _interact_ray: RayCast3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D/InteractRay
@onready var _head_check: RayCast3D = $HeadCheck

var _stand_camera_height := 0.0
var _ground_speed := 0.0
var _base_fov := 70.0
var _camera_dip := 0.0
var _stamina_regen_timer := 0.0
var _breath_recovering := false
var _threat_level := 0.0
var _bpm_spike := 0.0
var _heartbeat_critical := false
var _last_emitted_bpm := -1.0
var _step_accum := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _surface_noise: Dictionary[int, float] = {} # source instance id -> multiplier
var _surface_noise_mult := 1.0
var _focused: Interactable
var _last_prompt := ""
var _pre_hide_position := Vector3.ZERO
var _is_dead := false
var _wall_run_left := 0.0
var _wall_normal := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"player")
	stamina = max_stamina
	breath = max_breath
	heartbeat_bpm = resting_bpm
	_stand_camera_height = _camera_yaw.position.y
	_base_fov = _camera.fov
	_interact_ray.add_exception(self)
	_head_check.add_exception(self)
	_head_check.position.y = crouch_height - 0.05
	_head_check.target_position = Vector3(0.0, stand_height - crouch_height + 0.1, 0.0)
	_apply_collider_height(stand_height)
	_emit_all_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and state != State.DISABLED:
			_rotate_camera((event as InputEventMouseMotion).screen_relative)
		return
	if state == State.DISABLED:
		return
	if event.is_action_pressed(&"interact"):
		_try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"crouch") and state != State.HIDDEN:
		_toggle_crouch()


func _physics_process(delta: float) -> void:
	# HIDDEN and the Level 3 abilities (CLIMB / SWING) drive the body themselves.
	if state != State.HIDDEN and state != State.CLIMB and state != State.SWING:
		_process_movement(delta)
	_update_stamina(delta)
	_update_breath(delta)
	_update_heartbeat(delta)
	_update_camera_fx(delta)
	_update_interaction()


# =========================================================================
# Public API (used by levels, AI, hide spots, future ability components)
# =========================================================================

func set_input_enabled(enabled: bool) -> void:
	if _is_dead:
		return
	if enabled:
		if state == State.DISABLED:
			_set_state(State.IDLE)
	else:
		if state == State.HIDDEN:
			exit_hiding()
		velocity = Vector3(0.0, velocity.y, 0.0)
		_set_state(State.DISABLED)


## Hide the body during first-person cutscenes.
func set_model_visible(value: bool) -> void:
	_visual.visible = value


func set_facing(yaw: float) -> void:
	_camera_yaw.rotation.y = yaw
	_visual.rotation.y = yaw


func kill(reason: String) -> void:
	if _is_dead:
		return
	_is_dead = true
	_set_state(State.DISABLED)
	EventBus.player_died.emit(reason)


## Used by the climbing / swinging abilities to take over the body.
func set_movement_state(new_state: State) -> void:
	_set_state(new_state)


## True while the player is running along a wall (Level 3).
func is_wall_running() -> bool:
	return _wall_run_left > 0.0


## Broadcast a sound for AI. `loudness` = hearing radius in meters.
func make_noise(loudness: float, affected_by_surface: bool = true) -> void:
	var final_loudness := loudness * (_surface_noise_mult if affected_by_surface else 1.0)
	if final_loudness > 0.0:
		EventBus.noise_emitted.emit(global_position, final_loudness, self)


## Surface zones (water, carpet, metal grating) push a noise multiplier on
## body_entered and pop it on body_exited. The loudest active surface wins.
func push_surface_noise(source: Object, multiplier: float) -> void:
	_surface_noise[source.get_instance_id()] = multiplier
	_recalculate_surface_noise()


func pop_surface_noise(source: Object) -> void:
	_surface_noise.erase(source.get_instance_id())
	_recalculate_surface_noise()


## Enemies call this every physics frame while near the player (0..1).
func report_threat(intensity: float) -> void:
	_threat_level = maxf(_threat_level, clampf(intensity, 0.0, 1.0))


## Sudden scare (jump-scare, alarm, gasp).
func add_heartbeat_spike(bpm: float) -> void:
	_bpm_spike += bpm


func get_heartbeat_normalized() -> float:
	return clampf(inverse_lerp(resting_bpm, max_bpm, heartbeat_bpm), 0.0, 1.0)


func has_stamina(amount: float) -> bool:
	return stamina >= amount


## For abilities (swing, dyno jump, climbing). Returns false if not enough.
func consume_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	_set_stamina(stamina - amount)
	_stamina_regen_timer = stamina_regen_delay
	return true


func restore_stamina(amount: float) -> void:
	_set_stamina(stamina + amount)


## `view_camera`: optional first-person camera inside the hiding spot.
func enter_hiding(spot: Node3D, view_camera: Camera3D = null) -> void:
	if state == State.HIDDEN or _is_dead:
		return
	current_hide_spot = spot
	if view_camera:
		view_camera.make_current()
	_pre_hide_position = global_position
	velocity = Vector3.ZERO
	global_position = spot.global_position
	_visual.visible = false
	_collision.set_deferred(&"disabled", true)
	_set_state(State.HIDDEN)
	EventBus.player_hidden_changed.emit(true)


func exit_hiding() -> void:
	if state != State.HIDDEN:
		return
	global_position = _pre_hide_position
	current_hide_spot = null
	_camera.make_current()
	_visual.visible = true
	_collision.set_deferred(&"disabled", false)
	_set_state(State.IDLE)
	EventBus.player_hidden_changed.emit(false)


func get_camera() -> Camera3D:
	return _camera


func get_flashlight() -> Flashlight:
	return $CameraYaw/CameraPitch/Flashlight as Flashlight


# =========================================================================
# Movement
# =========================================================================

func _process_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if state != State.DISABLED:
		input_dir = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")

	var on_floor := is_on_floor()
	var wall_running := wall_run_enabled and not on_floor and _update_wall_run(delta, input_dir)
	if not on_floor:
		velocity += get_gravity() * delta * (wall_run_gravity if wall_running else 1.0)
	elif state != State.DISABLED and not is_crouching and Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_velocity
		make_noise(jump_noise)

	_update_state(input_dir, on_floor)

	# Camera-relative direction. The body never rotates; only Visual turns.
	var direction := _camera_yaw.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	var target_velocity := direction * _speed_for_state()
	var weight := 1.0 - exp(-acceleration * (1.0 if on_floor else air_control) * delta)
	velocity.x = lerpf(velocity.x, target_velocity.x, weight)
	velocity.z = lerpf(velocity.z, target_velocity.z, weight)

	if direction.length_squared() > 0.001:
		var target_yaw := atan2(-direction.x, -direction.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

	_fall_speed = maxf(-velocity.y, 0.0)
	move_and_slide()
	_handle_footsteps(delta)


## Sticks to a wall while you hold forward against it with enough speed.
## Returns true while the run is active.
func _update_wall_run(delta: float, input_dir: Vector2) -> bool:
	if is_on_floor() or input_dir.y >= 0.0 or velocity.y > 2.0:
		_wall_run_left = 0.0
		return false
	if not is_on_wall():
		_wall_run_left = 0.0
		return false
	var normal := get_wall_normal()
	if _wall_run_left <= 0.0:
		if Vector2(velocity.x, velocity.z).length() < wall_run_min_speed:
			return false
		_wall_run_left = wall_run_time
		_wall_normal = normal
		make_noise(walk_noise)
	_wall_run_left -= delta
	if _wall_run_left <= 0.0:
		return false
	# Slide along the wall in the direction we were already heading.
	var along := normal.cross(Vector3.UP).normalized()
	var heading := Vector3(velocity.x, 0.0, velocity.z)
	if heading.dot(along) < 0.0:
		along = -along
	velocity.x = along.x * wall_run_speed
	velocity.z = along.z * wall_run_speed
	velocity.y = maxf(velocity.y, -1.0)
	if Input.is_action_just_pressed(&"jump"):
		# Kick off the wall.
		velocity = along * wall_run_speed + normal * 4.0 + Vector3.UP * jump_velocity
		_wall_run_left = 0.0
	return true


func _update_state(input_dir: Vector2, on_floor: bool) -> void:
	if state == State.DISABLED:
		return
	var next: State
	if not on_floor:
		next = State.AIRBORNE
	elif is_crouching:
		next = State.CROUCH
	elif input_dir.is_zero_approx():
		next = State.IDLE
	elif Input.is_action_pressed(&"sprint") and not is_exhausted and stamina > 0.0:
		next = State.RUN
	else:
		next = State.WALK
	_set_state(next)


func _speed_for_state() -> float:
	match state:
		State.WALK:
			_ground_speed = walk_speed
		State.RUN:
			_ground_speed = run_speed
		State.CROUCH:
			_ground_speed = crouch_speed
		State.AIRBORNE:
			return _ground_speed # keep take-off momentum
		State.DISABLED, State.HIDDEN:
			return 0.0
	return _ground_speed


func _handle_footsteps(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		var land_loudness := land_noise * clampf(_fall_speed / 8.0, 0.25, 1.5)
		make_noise(land_loudness)
		footstep.emit(land_loudness)
		_camera_dip = minf(_fall_speed * land_camera_dip, 0.25)
		_step_accum = 0.0
	elif on_floor and (state == State.WALK or state == State.RUN or state == State.CROUCH):
		_step_accum += Vector2(velocity.x, velocity.z).length() * delta
		var step_length := _step_length()
		if _step_accum >= step_length:
			_step_accum -= step_length
			var loudness := _step_noise()
			make_noise(loudness)
			footstep.emit(loudness * _surface_noise_mult)
	_was_on_floor = on_floor


## One footstep per half animation stride, so noise lines up with the feet.
func _step_length() -> float:
	match state:
		State.RUN:
			return run_step_length
		State.CROUCH:
			return crouch_step_length
	return walk_step_length


func _step_noise() -> float:
	match state:
		State.RUN:
			return run_noise
		State.CROUCH:
			return crouch_noise
	return walk_noise


func _toggle_crouch() -> void:
	if is_crouching:
		_head_check.force_raycast_update()
		if _head_check.is_colliding():
			return # ceiling too low to stand up
		is_crouching = false
		_apply_collider_height(stand_height)
	else:
		is_crouching = true
		_apply_collider_height(crouch_height)


func _apply_collider_height(height: float) -> void:
	_capsule.height = height
	_collision.position.y = height * 0.5


# =========================================================================
# Camera
# =========================================================================

func _rotate_camera(relative: Vector2) -> void:
	_camera_yaw.rotate_y(-relative.x * mouse_sensitivity)
	_camera_pitch.rotation.x = clampf(
		_camera_pitch.rotation.x - relative.y * mouse_sensitivity,
		deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func _update_camera_fx(delta: float) -> void:
	var target := _stand_camera_height - ((stand_height - crouch_height) if is_crouching else 0.0) - _camera_dip
	_camera_yaw.position.y = lerpf(_camera_yaw.position.y, target, 1.0 - exp(-12.0 * delta))
	_camera_dip = move_toward(_camera_dip, 0.0, 0.8 * delta)
	var target_fov := _base_fov + (sprint_fov_boost if state == State.RUN else 0.0)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-4.0 * delta))


# =========================================================================
# Stats: stamina / breath / heartbeat
# =========================================================================

func _update_stamina(delta: float) -> void:
	if state == State.RUN:
		_set_stamina(stamina - stamina_drain_rate * delta)
		_stamina_regen_timer = stamina_regen_delay
		if stamina <= 0.0:
			is_exhausted = true
	elif _stamina_regen_timer > 0.0:
		_stamina_regen_timer -= delta
	elif stamina < max_stamina:
		_set_stamina(stamina + stamina_regen_rate * delta)
	if is_exhausted and stamina >= min_stamina_to_run:
		is_exhausted = false


func _set_stamina(value: float) -> void:
	value = clampf(value, 0.0, max_stamina)
	if value == stamina:
		return
	stamina = value
	EventBus.player_stamina_changed.emit(stamina, max_stamina)


func _update_breath(delta: float) -> void:
	var previous := breath
	var wants_hold := state != State.DISABLED and Input.is_action_pressed(&"hold_breath")
	if wants_hold and not _breath_recovering and breath > 0.0:
		is_holding_breath = true
		breath = maxf(breath - delta, 0.0)
		if breath <= 0.0:
			_gasp()
	else:
		is_holding_breath = false
		breath = minf(breath + breath_regen_rate * delta, max_breath)
		if _breath_recovering and breath >= max_breath * 0.5:
			_breath_recovering = false
	if breath != previous:
		EventBus.player_breath_changed.emit(breath, max_breath)


## Ran out of breath: loud gasp that ignores surface and spikes heartbeat.
func _gasp() -> void:
	is_holding_breath = false
	_breath_recovering = true
	add_heartbeat_spike(gasp_bpm_spike)
	make_noise(gasp_noise, false)
	gasped.emit()


func _update_heartbeat(delta: float) -> void:
	var target := resting_bpm + threat_bpm_bonus * _threat_level + _bpm_spike
	if state == State.RUN:
		target += run_bpm_bonus

	# Calm Down: holding breath inside a hiding spot fully calms the heart.
	var calm := 0.0
	if is_holding_breath:
		calm = 1.0 if is_hidden else 0.5
	elif is_hidden:
		calm = 0.2
	target = minf(lerpf(target, resting_bpm, calm), max_bpm)

	var rate := bpm_rise_rate if target > heartbeat_bpm else bpm_fall_rate + calm * calm_bpm_rate
	heartbeat_bpm = move_toward(heartbeat_bpm, target, rate * delta)
	_bpm_spike = move_toward(_bpm_spike, 0.0, spike_decay_rate * delta)
	_threat_level = 0.0 # enemies re-report every frame

	if absf(heartbeat_bpm - _last_emitted_bpm) >= 0.5:
		_last_emitted_bpm = heartbeat_bpm
		EventBus.player_heartbeat_changed.emit(heartbeat_bpm, get_heartbeat_normalized())

	var critical := heartbeat_bpm >= critical_bpm or (
		_heartbeat_critical and heartbeat_bpm > critical_bpm - critical_hysteresis)
	if critical != _heartbeat_critical:
		_heartbeat_critical = critical
		EventBus.player_heartbeat_critical.emit(critical)


func _emit_all_stats() -> void:
	EventBus.player_stamina_changed.emit(stamina, max_stamina)
	EventBus.player_breath_changed.emit(breath, max_breath)
	EventBus.player_heartbeat_changed.emit(heartbeat_bpm, get_heartbeat_normalized())


# =========================================================================
# Interaction
# =========================================================================

func _update_interaction() -> void:
	_focused = null
	var prompt := ""
	if state == State.HIDDEN:
		prompt = "PROMPT_LEAVE_HIDING"
	elif state != State.DISABLED and _interact_ray.is_colliding():
		var hit := _interact_ray.get_collider() as Interactable
		if hit and hit.can_interact(self):
			var head := _camera_yaw.global_position
			var to_hit := _interact_ray.get_collision_point() - head
			var in_front := to_hit.dot(-_camera.global_basis.z) > 0.0
			if in_front and to_hit.length() <= interact_range:
				_focused = hit
				prompt = hit.get_prompt()
	if prompt != _last_prompt:
		_last_prompt = prompt
		EventBus.interaction_prompt_changed.emit(prompt)


func _try_interact() -> void:
	if state == State.HIDDEN:
		exit_hiding()
	elif _focused:
		_focused.interact(self)


# =========================================================================
# State machine
# =========================================================================

func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old_state := state
	state = new_state
	state_changed.emit(new_state, old_state)


func _recalculate_surface_noise() -> void:
	if _surface_noise.is_empty():
		_surface_noise_mult = 1.0
		return
	_surface_noise_mult = 0.0
	for multiplier: float in _surface_noise.values():
		_surface_noise_mult = maxf(_surface_noise_mult, multiplier)
