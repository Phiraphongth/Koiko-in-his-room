extends LevelBase
## Level 4 director: "The Pressure Valve" (♣ 9). 5-minute timer, played alone.
##
## The control room (west) has the gas diagram and the pressure gauge; the
## valve room (east) has the four valves. One passage joins them, so every
## correction is a run between the rooms.
##   Every round: bring the pressure to the target and HOLD it there while the
##   leak keeps pushing it up (faster each round). Each new round reroutes the
##   valves, so the diagram has to be read again.
##   00:45 the gas leaks: vision blurs and pushes can surge +2.
##   02:00 the power fails: the repeater in the valve room goes dark, and the
##   only way to read the pressure is the gauge back in the control room.
##   Final: both pressure plates must be held down at once and nobody else is
##   here to stand on one: push a crate onto each while the pressure climbs.
## Walking out with few vents earns the Good Ending (GOOD_ENDING_MAX_VENTS).
## Geometry: tools/scene_builder/build_level_4.gd.

const ROUNDS := 5
## The pressure blows at these values: the safe band is everything between.
const SAFE_MIN := 3
const SAFE_MAX := 17
const START_PRESSURE := 10
## Targets are picked at least this far from the current pressure.
const MIN_TARGET_DISTANCE := 4
## The pressure must stay within ±HOLD_TOLERANCE of the target this long.
const HOLD_TIME := 10.0
const HOLD_TOLERANCE := 1
const HOLD_BAR_STEPS := 8
## Seconds between leak pushes, one entry per round (the last one also covers
## the final phase).
const DRIFT_INTERVALS: Array[float] = [12.0, 10.0, 8.0, 7.0, 6.0]
const SURGE_CHANCE := 0.3 # once the gas leaks, some pushes are +2
const DANGER_MARGIN := 2 # gauge turns red this close to an edge
const WRONG_PENALTY := 20.0
const MAX_VENTS := 3 # the third one ignites the gas
const GOOD_ENDING_MAX_VENTS := 1
## What the valves can do. Every round deals these out to the valves anew.
const VALVE_DELTAS: Array[int] = [-3, 1, -1, 2]
const TURN_TIME := 0.9

@onready var _fx: HorrorFX = %HorrorFX
@onready var _announcer: Announcer = %Announcer
@onready var _diagram: Node3D = %Diagram
@onready var _valves: Node3D = %Valves
@onready var _gauge: Label3D = %Gauge
@onready var _target_label: Label3D = %TargetLabel
@onready var _repeater: Label3D = %Repeater
@onready var _control_plate: PressurePlate = %ControlPlate
@onready var _valve_plate: PressurePlate = %ValvePlate
@onready var _control_crate: Node3D = %ControlCrate
@onready var _valve_crate: Node3D = %ValveCrate
@onready var _control_crate_handle: Interactable = %ControlCrateHandle
@onready var _valve_crate_handle: Interactable = %ValveCrateHandle
@onready var _exit_door: Door = %ExitDoor
@onready var _exit_trigger: TriggerZone = %ExitTrigger
@onready var _gas: Node3D = %GasFog
@onready var _alarm: ProceduralSound = %Alarm

var pressure := START_PRESSURE
var target := START_PRESSURE
var _round := 0
var _final_phase := false
var _door_open := false
var _escaped := false
var _drift_timer := 0.0
var _leaking := false
var _repeater_dead := false
var _hold := 0.0
var _vents := 0
var _in_danger := false
var _beep_timer := 0.0
var _told_own_weight := false
## _deltas[i] is what valve i does this round.
var _deltas: Array[int] = VALVE_DELTAS.duplicate()
var _turning: Array[bool] = []
var _gauge_origin := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	ProceduralAudio.preload_sounds([&"alarm", &"beep", &"keycard", &"shutter", &"clang", &"click",
		&"step_0", &"step_1", &"step_2", &"step_3"])
	super()
	_rng.randomize()
	_gauge_origin = _gauge.position
	_gas.visible = false
	for i in _valves.get_child_count():
		_turning.append(false)
		var handle := _valves.get_child(i).get_node("Handle") as Interactable
		handle.interacted.connect(_turn_valve.bind(i).unbind(1))
	_control_crate_handle.interacted.connect(_push_crate.bind(_control_crate_handle, _control_crate, _control_plate).unbind(1))
	_valve_crate_handle.interacted.connect(_push_crate.bind(_valve_crate_handle, _valve_crate, _valve_plate).unbind(1))
	_control_crate_handle.enabled = false
	_valve_crate_handle.enabled = false
	_exit_trigger.triggered.connect(_on_exit.unbind(1))
	_intro()


func _process(delta: float) -> void:
	super(delta)
	if not is_running or _door_open or _round == 0:
		return
	_drift_timer -= delta
	if _drift_timer <= 0.0:
		_drift_timer = _drift_interval()
		# The leak keeps pushing the pressure up; once the gas is out it surges.
		var surge := _leaking and _rng.randf() < SURGE_CHANCE
		_apply_pressure(2 if surge else 1, true)
		if not is_running: # that push was the last vent
			return
	if _final_phase:
		_check_plates()
	else:
		_update_hold(delta)
	_update_danger(delta)


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
	target = _pick_target()
	_hold = 0.0
	_drift_timer = _drift_interval()
	_reroute()
	_refresh_displays()
	EventBus.objective_changed.emit(Localization.t("L4_OBJ_ROUND", [_round, ROUNDS, target, int(HOLD_TIME)]))
	EventBus.subtitle_requested.emit(Localization.t("L4_SAY_ROUND", [target]), 3.5)


## A target at least MIN_TARGET_DISTANCE away, so every round takes several turns.
func _pick_target() -> int:
	var candidates: Array[int] = []
	for value in range(SAFE_MIN + 2, SAFE_MAX - 1):
		if absi(value - pressure) >= MIN_TARGET_DISTANCE:
			candidates.append(value)
	if candidates.is_empty():
		return START_PRESSURE
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _drift_interval() -> float:
	return DRIFT_INTERVALS[clampi(_round - 1, 0, DRIFT_INTERVALS.size() - 1)]


## Deals the valve effects out again and rewrites the diagram. What the player
## memorised last round is now wrong.
func _reroute() -> void:
	var previous := _deltas.duplicate()
	while _deltas == previous:
		for i in range(_deltas.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var swap := _deltas[i]
			_deltas[i] = _deltas[j]
			_deltas[j] = swap
	for i in _deltas.size():
		var row := _diagram.get_node("Row%d" % i) as Label3D
		row.text = "%s  VALVE %d     %+d bar" % [_symbol_of(i), i + 1, _deltas[i]]
	_play_at(_diagram.get_child(0), &"click")
	if _round > 1:
		EventBus.subtitle_requested.emit("L4_SAY_REROUTED", 3.0)


## The player is at a valve. The effect is locked in when the turn starts, so a
## reroute mid-turn doesn't change it.
func _turn_valve(index: int) -> void:
	if not is_running or _door_open or _turning[index]:
		return
	_turning[index] = true
	var delta := _deltas[index]
	var wheel := _valves.get_child(index) as Node3D
	var mesh := wheel.get_node("Wheel") as Node3D
	var rest := mesh.basis
	_play_at(wheel, &"clang")
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(angle: float) -> void: mesh.basis = rest * Basis(Vector3.UP, angle),
		0.0, signf(delta) * PI, TURN_TIME)
	await tween.finished
	_turning[index] = false
	if is_running and not _door_open:
		_apply_pressure(delta, false)


func _apply_pressure(delta: int, from_leak: bool) -> void:
	pressure = clampi(pressure + delta, SAFE_MIN, SAFE_MAX)
	_refresh_displays()
	if from_leak and delta > 1:
		EventBus.subtitle_requested.emit("L4_SAY_SURGE", 2.5)
	elif from_leak and _round == 1:
		EventBus.subtitle_requested.emit("L4_SAY_DRIFT", 2.5)
	if pressure <= SAFE_MIN or pressure >= SAFE_MAX:
		_vent()


## On target the hold bar fills; slipping off it starts the bar over.
func _update_hold(delta: float) -> void:
	if absi(pressure - target) > HOLD_TOLERANCE:
		if _hold > 0.0:
			_hold = 0.0
			_refresh_displays()
			EventBus.subtitle_requested.emit("L4_SAY_HOLD_LOST", 2.0)
		return
	if _hold == 0.0:
		EventBus.subtitle_requested.emit("L4_SAY_HOLD", 2.0)
	var steps_before := _hold_steps()
	_hold += delta
	if _hold >= HOLD_TIME:
		_round_complete()
	elif _hold_steps() != steps_before:
		_play_at(_gauge, &"click")
		_refresh_displays()


func _hold_steps() -> int:
	return int(_hold / HOLD_TIME * HOLD_BAR_STEPS)


## Near either edge the gauges shake, beep faster and the heart races.
func _update_danger(delta: float) -> void:
	var margin := mini(pressure - SAFE_MIN, SAFE_MAX - pressure)
	var intensity := clampf(float(DANGER_MARGIN + 2 - margin) / (DANGER_MARGIN + 1), 0.0, 1.0)
	player.report_threat(intensity)
	var shake := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), 0.0)
	_gauge.position = _gauge_origin + shake * 0.012 * intensity
	_in_danger = margin <= DANGER_MARGIN
	if intensity <= 0.0:
		return
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_beep_timer = 0.25 * margin
		_play_at(_gauge, &"beep")
		if not _repeater_dead:
			_play_at(_repeater, &"beep")


func _round_complete() -> void:
	_play_at(_gauge, &"keycard")
	EventBus.subtitle_requested.emit("L4_SAY_STABLE", 2.5)
	_next_round()


## Out of the safe band: gas, lost time, and the pressure thrown well away
## from the target. The last vent ignites it.
func _vent() -> void:
	_vents += 1
	_alarm.play()
	player.add_heartbeat_spike(35.0)
	if _vents >= MAX_VENTS:
		_explode()
		return
	add_time(-WRONG_PENALTY)
	_hold = 0.0
	var vented := target - MIN_TARGET_DISTANCE if target >= START_PRESSURE else target + MIN_TARGET_DISTANCE
	pressure = clampi(vented, SAFE_MIN + 3, SAFE_MAX - 3)
	_refresh_displays()
	EventBus.subtitle_requested.emit(Localization.t("L4_SAY_OVERPRESSURE", [_vents, MAX_VENTS]), 3.5)
	await _wait(2.0)
	_alarm.stop()


func _refresh_displays() -> void:
	var color := _pressure_color()
	_gauge.text = "%02d" % pressure
	_gauge.modulate = color
	if _final_phase:
		_target_label.text = "WEIGH BOTH PLATES\nVENTS %d/%d" % [_vents, MAX_VENTS]
	else:
		var filled := _hold_steps()
		_target_label.text = "TARGET  %02d ±%d\n[%s%s]\nVENTS %d/%d" % [target, HOLD_TOLERANCE,
			"|".repeat(filled), ".".repeat(HOLD_BAR_STEPS - filled), _vents, MAX_VENTS]
	if not _repeater_dead:
		_repeater.text = "%02d" % pressure if _final_phase else "%02d  >  %02d" % [pressure, target]
		_repeater.modulate = color


func _pressure_color() -> Color:
	if mini(pressure - SAFE_MIN, SAFE_MAX - pressure) <= DANGER_MARGIN:
		return Color(1.0, 0.25, 0.2)
	if not _final_phase and absi(pressure - target) <= HOLD_TOLERANCE:
		return Color(0.4, 1.0, 0.5)
	return Color(1.0, 0.8, 0.3)


func _symbol_of(index: int) -> String:
	return (_valves.get_child(index).get_node("Symbol") as Label3D).text


# =========================================================================
# Timeline
# =========================================================================

func _on_timeline_event(event_id: StringName) -> void:
	match event_id:
		&"gas_leak":
			_leaking = true
			_gas.visible = true
			_gas_fog_fallback()
			_fx.set_blur(1.2)
			player.add_heartbeat_spike(20.0)
			_announcer.announce("L4_PA_LEAK", false)
			EventBus.subtitle_requested.emit("L4_SAY_LEAK", 4.0)
		&"power_cut":
			_repeater_dead = true
			_repeater.text = "--"
			_repeater.modulate = Color(0.25, 0.25, 0.25)
			_play_at(_repeater, &"shutter")
			_announcer.announce("L4_PA_POWER", false)
			EventBus.subtitle_requested.emit("L4_SAY_POWER", 4.0)


## FogVolume needs Forward+. On the Compatibility renderer (web build) tint the
## room's distance fog green instead, so the leak still reads on screen.
func _gas_fog_fallback() -> void:
	if not SettingsManager.is_compatibility_renderer():
		return
	var world := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var env := world.environment
	env.fog_enabled = true
	var tween := create_tween().set_parallel()
	tween.tween_property(env, ^"fog_light_color", Color(0.2, 0.34, 0.14), 5.0)
	tween.tween_property(env, ^"fog_density", env.fog_density + 0.06, 5.0)


# =========================================================================
# Final phase: two plates, one player
# =========================================================================

func _begin_final_phase() -> void:
	_final_phase = true
	_hold = 0.0
	_drift_timer = _drift_interval()
	_control_crate_handle.enabled = true
	_valve_crate_handle.enabled = true
	_refresh_displays()
	_announcer.announce("L4_PA_FINAL")
	EventBus.objective_changed.emit("L4_OBJ_FINAL")
	EventBus.subtitle_requested.emit("L4_SAY_FINAL", 6.0)


func _push_crate(handle: Interactable, crate: Node3D, plate: PressurePlate) -> void:
	handle.enabled = false
	var target_position := plate.global_position + Vector3(0, crate.global_position.y - plate.global_position.y, 0)
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(crate, "global_position", target_position, 1.2)
	_play_at(crate, &"clang")
	EventBus.subtitle_requested.emit("L4_SAY_CRATE_PUSHED", 3.0)


## Both plates must be down, and not by the player: standing on one means
## you are still in the room when the other door would need you.
func _check_plates() -> void:
	if not (_control_plate.is_pressed and _valve_plate.is_pressed):
		return
	if _control_plate.overlaps_body(player) or _valve_plate.overlaps_body(player):
		if not _told_own_weight:
			_told_own_weight = true
			EventBus.subtitle_requested.emit("L4_SAY_OWN_WEIGHT", 4.0)
		return
	_door_open = true
	_gauge.position = _gauge_origin
	_alarm.stop()
	_exit_door.open()
	_announcer.announce("L4_PA_DOOR_OPEN", false)
	EventBus.subtitle_requested.emit("L4_SAY_DOOR_OPEN", 4.0)
	EventBus.objective_changed.emit("L4_OBJ_LEAVE")


func _on_exit() -> void:
	if _escaped or not _door_open:
		return
	_escaped = true
	is_running = false
	player.set_input_enabled(false)
	EventBus.good_ending_earned.emit(_vents <= GOOD_ENDING_MAX_VENTS)
	await _fx.blink_to(1.0, 1.2)
	complete_level()


func _on_time_up() -> void:
	_explode()


func _explode() -> void:
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
