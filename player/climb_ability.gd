class_name ClimbAbility
extends Node
## Level 3 movement: climbing walls and swinging from bars.
## Child of Player; it takes over the body while attached and hands control
## back on release. Levels switch it on with `enabled = true`.
##
##   Climb:  walk into a ClimbPanel, [W/A/S/D] to move over the face,
##           [Space] to let go and jump off. Stamina drains while hanging on.
##   Swing:  jump into a SwingBar to grab it. You swing back and forth;
##           [Space] releases along the swing, so time it for distance.

const CLIMB_SPEED := 2.2
const CLIMB_STAMINA_PER_SECOND := 9.0
const CLIMB_JUMP := 5.0
const CLIMB_PUSH := 2.5
const SWING_GRAVITY := 11.0
const SWING_STAMINA := 6.0
const SWING_RELEASE_BOOST := Vector3(1.25, 1.45, 1.25)
const GRAB_COOLDOWN := 0.8
const RELEASE_UP_SPEED := 2.0 ## don't re-grab while still flying up from a release

@export var enabled := false

@onready var _player: Player = get_parent() as Player

var _panel: ClimbPanel
var _bar: SwingBar
var _swing_angle := 0.0     # radians from straight down, in the swing plane
var _swing_velocity := 0.0
var _swing_axis := Vector3.FORWARD
var _cooldown := 0.0
var _ignore: Node = null # the thing we just let go of


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown <= 0.0:
		_ignore = null
	if _panel:
		_climb(delta)
	elif _bar:
		_swing(delta)
	elif _cooldown <= 0.0:
		_try_grab()


func release() -> void:
	_ignore = _panel if _panel else _bar
	_panel = null
	_bar = null
	_cooldown = GRAB_COOLDOWN
	if _player.state == Player.State.CLIMB or _player.state == Player.State.SWING:
		_player.set_movement_state(Player.State.AIRBORNE)


# =========================================================================
# Grabbing
# =========================================================================

func _try_grab() -> void:
	if _player.state == Player.State.DISABLED or _player.state == Player.State.HIDDEN:
		return
	if _player.velocity.y > RELEASE_UP_SPEED:
		return # still rising from the last jump
	for area in _overlapping_areas():
		if area == _ignore:
			continue
		if area is SwingBar:
			_grab_bar(area as SwingBar)
			return
		if area is ClimbPanel and not (area as ClimbPanel).is_broken and _player.has_stamina(1.0):
			_grab_panel(area as ClimbPanel)
			return


## Areas the player body is currently inside (panels and bars monitor the player layer).
func _overlapping_areas() -> Array[Area3D]:
	var found: Array[Area3D] = []
	for area in _player.get_tree().get_nodes_in_group(&"climbable"):
		var node := area as Area3D
		if node and node.monitoring and node.overlaps_body(_player):
			found.append(node)
	return found


func _grab_panel(panel: ClimbPanel) -> void:
	_panel = panel
	panel.touched()
	if not panel.broke.is_connected(_on_panel_broke):
		panel.broke.connect(_on_panel_broke, CONNECT_ONE_SHOT)
	_player.velocity = Vector3.ZERO
	_player.set_movement_state(Player.State.CLIMB)
	_player.make_noise(2.0)


func _grab_bar(bar: SwingBar) -> void:
	_bar = bar
	_player.consume_stamina(SWING_STAMINA)
	# Swing in the plane the player is already moving through.
	var heading := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if heading.length() < 0.5:
		heading = -_player.global_basis.z
	_swing_axis = heading.normalized()
	var offset := _player.global_position - bar.global_position
	_swing_angle = clampf(atan2(offset.dot(_swing_axis), maxf(-offset.y, 0.1)), -1.2, 1.2)
	_swing_velocity = _player.velocity.dot(_swing_axis) / maxf(bar.rope_length, 0.5)
	_player.set_movement_state(Player.State.SWING)
	_player.make_noise(3.0)


func _on_panel_broke(_panel: ClimbPanel) -> void:
	release()
	_player.add_heartbeat_spike(30.0)


# =========================================================================
# Climbing
# =========================================================================

func _climb(delta: float) -> void:
	if _panel.is_broken or not _player.consume_stamina(CLIMB_STAMINA_PER_SECOND * delta):
		release()
		return
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# Up/down follows "forward/back", left/right follows the panel face.
	var face := _panel.global_basis.z    # panel +Z points away from the wall
	var right := _panel.global_basis.x
	var motion := (right * input.x + Vector3.UP * -input.y) * CLIMB_SPEED
	_player.velocity = motion
	_player.move_and_slide()
	# Stay glued to the face.
	var offset := (_player.global_position - _panel.global_position).dot(face)
	_player.global_position -= face * (offset - 0.45)

	if Input.is_action_just_pressed(&"jump"):
		var panel := _panel
		release()
		_player.velocity = face * CLIMB_PUSH + Vector3.UP * CLIMB_JUMP
		_player.make_noise(4.0)
		panel.touched()
	elif not _panel.overlaps_body(_player):
		release() # climbed off the top or the side


# =========================================================================
# Swinging
# =========================================================================

func _swing(delta: float) -> void:
	var rope: float = maxf(_bar.rope_length, 0.5)
	# Pendulum: angular acceleration = -(g / L) * sin(angle).
	_swing_velocity -= (SWING_GRAVITY / rope) * sin(_swing_angle) * delta
	_swing_velocity *= 0.999
	_swing_angle += _swing_velocity * delta
	var hang := _bar.global_position + _swing_axis * (sin(_swing_angle) * rope) \
		+ Vector3.DOWN * (cos(_swing_angle) * rope + 0.9)
	_player.velocity = Vector3.ZERO
	_player.global_position = hang
	if Input.is_action_just_pressed(&"jump"):
		var speed := _swing_velocity * rope
		var launch := _swing_axis * speed * SWING_RELEASE_BOOST.x
		launch.y = maxf(absf(speed) * 0.6, 3.0) * SWING_RELEASE_BOOST.y
		release()
		_player.velocity = launch
		_player.make_noise(4.0)
