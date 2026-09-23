extends LevelBase
## Level 4 director: "The Pressure Valve" (♣ 9). 9-minute timer.
##
## You are sealed in the control room with the gas diagram; the NPC is sealed
## in the valve room with the hardware. Neither of you can do the other's job,
## so you send symbols through the glass and they turn the valves.
##   03:00 the gas leaks: vision blurs and the pressure drifts on its own.
##   06:30 the radio dies: the console keeps the symbols but loses the words.
##   Final: both pressure plates must be held at once, and "the exit opens for
##   the room holding the switch last" — the way for BOTH of you to walk out
##   is to weigh the plates down with the crates instead of standing on them.
## Geometry: tools/scene_builder/build_level_4.gd.

const ROUNDS := 3
const SAFE_MIN := 0
const SAFE_MAX := 20
const DRIFT_INTERVAL := 20.0
const WRONG_PENALTY := 15.0
## Symbol -> pressure change. The player's wall diagram shows these; the NPC
## only ever sees the symbol you send.
const VALVE_DELTAS: Dictionary[StringName, int] = {
	&"valve_1": -3, &"valve_2": 1, &"valve_3": -1, &"valve_4": 2}

@onready var _fx: HorrorFX = %HorrorFX
@onready var _announcer: Announcer = %Announcer
@onready var _npc: NPCController = %Ally
@onready var _console: Node3D = %Console
@onready var _valves: Node3D = %Valves
@onready var _gauge: Label3D = %Gauge
@onready var _target_label: Label3D = %TargetLabel
@onready var _player_plate: PressurePlate = %PlayerPlate
@onready var _ally_plate: PressurePlate = %AllyPlate
@onready var _player_crate: Interactable = %PlayerCrateHandle
@onready var _player_crate_body: Node3D = %PlayerCrate
@onready var _ally_crate: Node3D = %AllyCrate
@onready var _player_door: Door = %PlayerDoor
@onready var _ally_door: Door = %AllyDoor
@onready var _exit_trigger: TriggerZone = %ExitTrigger
@onready var _gas: Node3D = %GasFog
@onready var _alarm: ProceduralSound = %Alarm

var pressure := 10
var target := 10
var _round := 0
var _final_phase := false
var _busy := false
var _escaped := false
var _drift_timer := DRIFT_INTERVAL
var _leaking := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	ProceduralAudio.preload_sounds([&"alarm", &"beep", &"keycard", &"shutter", &"clang", &"click",
		&"step_0", &"step_1", &"step_2", &"step_3"])
	super()
	_rng.randomize()
	_gas.visible = false
	for button: SignalButton in _console.get_children():
		button.sent.connect(_on_signal)
	_npc.interaction_finished.connect(_on_npc_finished)
	_npc.command_refused.connect(func(_reason: StringName) -> void:
		EventBus.subtitle_requested.emit("L4_SAY_REFUSED", 3.0))
	_player_crate.interacted.connect(_on_player_crate.unbind(1))
	_player_plate.pressed.connect(_on_plate_changed.unbind(1))
	_player_plate.released.connect(_on_plate_changed)
	_ally_plate.pressed.connect(_on_plate_changed.unbind(1))
	_ally_plate.released.connect(_on_plate_changed)
	_exit_trigger.triggered.connect(_on_exit.unbind(1))
	_player_crate.enabled = false
	_intro()


func _process(delta: float) -> void:
	super(delta)
	if not is_running or not _leaking or _final_phase:
		return
	_drift_timer -= delta
	if _drift_timer <= 0.0:
		_drift_timer = DRIFT_INTERVAL
		_apply_pressure(1, true) # the leak keeps pushing the pressure up


func _intro() -> void:
	GameManager.set_state(GameManager.State.CUTSCENE)
	player.set_input_enabled(false)
	await _wait(1.0)
	await _announcer.announce("L4_PA_INTRO")
	EventBus.message_requested.emit("L4_RULES_TITLE", "L4_RULES_BODY")
	await EventBus.message_closed
	player.set_input_enabled(false)
	await _announcer.announce("L4_PA_START")
	_alarm.play()
	await _wait(1.5)
	_alarm.stop()
	start_level()
	player.set_input_enabled(true)
	_next_round()


# =========================================================================
# The pressure puzzle
# =========================================================================

func _next_round() -> void:
	_round += 1
	if _round > ROUNDS:
		_begin_final_phase()
		return
	# Pick a target reachable with one or two valve turns.
	var deltas: Array = VALVE_DELTAS.values()
	var change := 0
	for i in _rng.randi_range(1, 2):
		change += deltas[_rng.randi_range(0, deltas.size() - 1)]
	target = clampi(pressure + change, SAFE_MIN + 2, SAFE_MAX - 2)
	if target == pressure:
		target = clampi(target + 2, SAFE_MIN + 2, SAFE_MAX - 2)
	_refresh_displays()
	EventBus.objective_changed.emit(Localization.t("L4_OBJ_ROUND", [_round, ROUNDS, target]))
	EventBus.subtitle_requested.emit(Localization.t("L4_SAY_ROUND", [target]), 3.5)


## A console key was pressed: relay the symbol to the NPC.
func _on_signal(command: StringName) -> void:
	if _busy or not is_running:
		return
	if _final_phase:
		_final_command(command)
		return
	if not VALVE_DELTAS.has(command):
		EventBus.subtitle_requested.emit("L4_SAY_NOT_YET", 2.5)
		return
	var valve := _valves.get_node_or_null(NodePath(String(command)))
	if valve == null:
		return
	_busy = true
	EventBus.subtitle_requested.emit(Localization.t("L4_SAY_SENT", [_symbol_of(command)]), 2.0)
	if not _npc.operate(valve, 1.4):
		_busy = false


func _on_npc_finished(target_node: Node3D) -> void:
	_busy = false
	if _final_phase or target_node == null:
		return
	var command := StringName(target_node.name)
	if not VALVE_DELTAS.has(command):
		return
	_apply_pressure(VALVE_DELTAS[command], false)
	if pressure == target:
		_round_complete()
	elif pressure <= SAFE_MIN or pressure >= SAFE_MAX:
		_overpressure()


func _apply_pressure(delta: int, from_leak: bool) -> void:
	pressure = clampi(pressure + delta, SAFE_MIN, SAFE_MAX)
	_refresh_displays()
	if from_leak:
		EventBus.subtitle_requested.emit("L4_SAY_DRIFT", 2.5)
	if pressure <= SAFE_MIN or pressure >= SAFE_MAX:
		_overpressure()


func _round_complete() -> void:
	_npc.change_stat(&"trust", 1)
	_play_at(_gauge, &"keycard")
	EventBus.subtitle_requested.emit("L4_SAY_STABLE", 2.5)
	_next_round()


## Wrong reading, wrong symbol, or the leak won: gas, time, and a shaken NPC.
func _overpressure() -> void:
	_alarm.play()
	_npc.change_stat(&"fear", 2)
	player.add_heartbeat_spike(35.0)
	add_time(-WRONG_PENALTY)
	pressure = clampi(pressure, SAFE_MIN + 3, SAFE_MAX - 3)
	_refresh_displays()
	EventBus.subtitle_requested.emit("L4_SAY_OVERPRESSURE", 3.5)
	await _wait(2.0)
	_alarm.stop()


func _refresh_displays() -> void:
	_gauge.text = "%02d" % pressure
	var danger := pressure <= SAFE_MIN + 3 or pressure >= SAFE_MAX - 3
	_gauge.modulate = Color(1.0, 0.25, 0.2) if danger else Color(0.4, 1.0, 0.5)
	_target_label.text = "TARGET  %02d" % target


func _symbol_of(command: StringName) -> String:
	for button: SignalButton in _console.get_children():
		if button.command == command:
			return button.symbol
	return "?"


# =========================================================================
# Timeline
# =========================================================================

func _on_timeline_event(event_id: StringName) -> void:
	match event_id:
		&"gas_leak":
			_leaking = true
			_gas.visible = true
			_fx.set_blur(1.2)
			_npc.change_stat(&"fear", 2)
			_announcer.announce("L4_PA_LEAK", false)
			EventBus.subtitle_requested.emit("L4_SAY_LEAK", 4.0)
		&"comms_error":
			for button: SignalButton in _console.get_children():
				button.hide_label()
			_announcer.announce("L4_PA_COMMS", false)
			EventBus.subtitle_requested.emit("L4_SAY_COMMS", 4.0)


# =========================================================================
# Final dilemma
# =========================================================================

func _begin_final_phase() -> void:
	_final_phase = true
	_player_crate.enabled = true
	_gauge.text = "--"
	_target_label.text = ""
	_announcer.announce("L4_PA_FINAL")
	EventBus.objective_changed.emit("L4_OBJ_FINAL")
	EventBus.subtitle_requested.emit("L4_SAY_FINAL", 6.0)


## In the final phase the console sends orders, not valve numbers.
func _final_command(command: StringName) -> void:
	match command:
		&"hold":
			if _npc.hold_position(_ally_plate.global_position):
				EventBus.subtitle_requested.emit("L4_SAY_ORDER_HOLD", 3.0)
		&"push":
			if _npc.operate(_ally_crate, 1.6):
				EventBus.subtitle_requested.emit("L4_SAY_ORDER_PUSH", 3.0)
				await _npc.interaction_finished
				_slide_crate(_ally_crate, _ally_plate)
		_:
			EventBus.subtitle_requested.emit("L4_SAY_VALVES_DONE", 2.5)


func _on_player_crate() -> void:
	_player_crate.enabled = false
	_slide_crate(_player_crate_body, _player_plate)
	EventBus.subtitle_requested.emit("L4_SAY_CRATE_PUSHED", 3.0)


func _slide_crate(crate: Node3D, plate: PressurePlate) -> void:
	var target_position := plate.global_position + Vector3(0, crate.global_position.y - plate.global_position.y, 0)
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(crate, "global_position", target_position, 1.2)
	_play_at(crate, &"clang")


## Fires whenever either plate changes: both down opens the valve.
func _on_plate_changed() -> void:
	if not _final_phase or _escaped:
		return
	if not (_player_plate.is_pressed and _ally_plate.is_pressed):
		return
	var player_is_free := not (_player_plate.holder is Player)
	var ally_is_free := not (_ally_plate.holder is NPCController)
	_player_door.open()
	if ally_is_free:
		_ally_door.open()
	EventBus.ally_fate_decided.emit(ally_is_free)
	if player_is_free and ally_is_free:
		_announcer.announce("L4_PA_BOTH_FREE", false)
		EventBus.subtitle_requested.emit("L4_SAY_BOTH_FREE", 4.0)
	elif not ally_is_free:
		EventBus.subtitle_requested.emit("L4_SAY_ALLY_TRAPPED", 5.0)
	EventBus.objective_changed.emit("L4_OBJ_LEAVE")


func _on_exit() -> void:
	if _escaped:
		return
	_escaped = true
	is_running = false
	player.set_input_enabled(false)
	await _fx.blink_to(1.0, 1.2)
	complete_level()


func _on_time_up() -> void:
	EventBus.subtitle_requested.emit("L4_SAY_EXPLOSION", 4.0)
	fail_level("explosion")


func _play_at(node: Node3D, id: StringName) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(id)
	sound.unit_size = 6.0
	node.add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
