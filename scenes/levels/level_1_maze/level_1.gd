extends LevelBase
## Level 1 director: "The Maze of Whispers" (♦ / ♣). 6-minute timer.
##
## Find three whisper stones in a labyrinth that rearranges itself every 35
## seconds (MazeGate panels rise and sink), then reach the exit. Laser
## tripwires are the automated alarms: three of them and the game is over,
## and each one costs 20 seconds and reshuffles the maze immediately.
## Geometry: tools/scene_builder/build_level_1.gd.

const STONES_NEEDED := 3
const CONFIGURATIONS := 3
const SHIFT_INTERVAL := 35.0
const MAX_ALARMS := 3
const ALARM_PENALTY := 20.0
const ALARM_COOLDOWN := 2.0

@onready var _fx: HorrorFX = %HorrorFX
@onready var _announcer: Announcer = %Announcer
@onready var _gates: Node3D = %Gates
@onready var _lasers: Node3D = %Lasers
@onready var _stones: Node3D = %Stones
@onready var _exit_door: Door = %ExitDoor
@onready var _exit_trigger: TriggerZone = %ExitTrigger
@onready var _shift_sound: ProceduralSound = %ShiftSound
@onready var _siren: ProceduralSound = %Siren

var _configuration := 0
var _collected := 0
var _alarms := 0
var _shift_timer := SHIFT_INTERVAL
var _last_alarm := -100.0
var _escaped := false


func _ready() -> void:
	ProceduralAudio.preload_sounds([&"whisper", &"stone", &"shift", &"laser", &"alarm", &"shutter",
		&"step_0", &"step_1", &"step_2", &"step_3"])
	super()
	for stone: WhisperStone in _stones.get_children():
		stone.collected.connect(_on_stone_collected)
	for laser: LaserTrap in _lasers.get_children():
		laser.tripped.connect(_on_laser_tripped.unbind(1))
	_exit_trigger.triggered.connect(_on_exit.unbind(1))
	_intro()


func _process(delta: float) -> void:
	super(delta)
	if not is_running:
		return
	_shift_timer -= delta
	if _shift_timer <= 0.0:
		_shift_maze()


func _intro() -> void:
	GameManager.set_state(GameManager.State.CUTSCENE)
	player.set_input_enabled(false)
	await _wait(1.0)
	await _announcer.announce("L1_PA_INTRO")
	EventBus.message_requested.emit("L1_RULES_TITLE", "L1_RULES_BODY")
	await EventBus.message_closed
	player.set_input_enabled(false)
	await _announcer.announce("L1_PA_START")
	start_level()
	player.set_input_enabled(true)
	player.get_flashlight().available = true
	EventBus.subtitle_requested.emit("L1_SAY_LISTEN", 4.0)
	_update_objective()


# =========================================================================
# The maze
# =========================================================================

## Raises one set of panels and sinks another: every route may change.
func _shift_maze() -> void:
	_shift_timer = SHIFT_INTERVAL
	_configuration = (_configuration + 1) % CONFIGURATIONS
	_shift_sound.play()
	player.add_heartbeat_spike(12.0)
	for gate: MazeGate in _gates.get_children():
		gate.apply_configuration(_configuration)
	EventBus.subtitle_requested.emit("L1_SAY_WALLS_MOVING", 2.5)


func _on_laser_tripped() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not is_running or now - _last_alarm < ALARM_COOLDOWN:
		return
	_last_alarm = now
	_alarms += 1
	_siren.play()
	player.add_heartbeat_spike(45.0)
	add_time(-ALARM_PENALTY)
	_shift_maze() # the maze punishes you by rearranging right away
	if _alarms >= MAX_ALARMS:
		EventBus.subtitle_requested.emit("L1_SAY_ALARM_FINAL", 4.0)
		await _wait(1.2)
		await _fx.blink_to(1.0, 1.0)
		player.kill("alarm")
		return
	EventBus.subtitle_requested.emit(Localization.t("L1_SAY_ALARM", [_alarms, MAX_ALARMS]), 3.5)
	_update_objective()


func _on_stone_collected(_stone: WhisperStone) -> void:
	_collected += 1
	player.add_heartbeat_spike(8.0)
	EventBus.subtitle_requested.emit(Localization.t("L1_SAY_STONE", [_collected, STONES_NEEDED]), 2.5)
	if _collected >= STONES_NEEDED:
		_open_exit()
	else:
		_update_objective()


func _open_exit() -> void:
	_exit_door.open()
	_announcer.announce("L1_PA_EXIT_OPEN", false)
	for laser: LaserTrap in _lasers.get_children():
		laser.disarm() # the maze gives up on you once the stones are gone
	EventBus.objective_changed.emit("L1_OBJ_EXIT")


func _on_exit() -> void:
	if _escaped or _collected < STONES_NEEDED:
		return
	_escaped = true
	is_running = false
	player.set_input_enabled(false)
	await _fx.blink_to(1.0, 1.0)
	complete_level()


func _update_objective() -> void:
	if _collected < STONES_NEEDED:
		EventBus.objective_changed.emit(Localization.t("L1_OBJ_STONES",
			[_collected, STONES_NEEDED, MAX_ALARMS - _alarms]))
	else:
		EventBus.objective_changed.emit("L1_OBJ_EXIT")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
