extends LevelBase
## Level 2 director: "The Blind Stalker" (♠ / ♥ 10). 10-minute timer.
## Lights out -> the Stalker is released -> find 3 keycards (container yard,
## flooded bay, terminal office) -> insert them at the control panel ->
## 30-second alarm draws the Stalker -> the exit opens -> escape.
## The collar: while the player's heart rate is critical it beeps, and the
## Stalker hears every beep. Geometry: tools/scene_builder/build_level_2.gd.

const RULES_TITLE := "L2_RULES_TITLE"
const RULES_BODY := "L2_RULES_BODY"
const KEYCARDS_NEEDED := 3
const ESCAPE_DELAY := 30.0
const COLLAR_NOISE := 11.0

@onready var _fx: HorrorFX = %HorrorFX
@onready var _announcer: Announcer = %Announcer
@onready var _navigation: NavigationRegion3D = %Navigation
@onready var _stalker: BlindStalker = %Stalker
@onready var _cage_door: Node3D = %CageDoor
@onready var _house_lights: Node3D = %HouseLights
@onready var _patrol_points: Node3D = %PatrolPoints
@onready var _panel: Interactable = %ControlPanel
@onready var _slot_lights: Node3D = %SlotLights
@onready var _panel_alarm: ProceduralSound3D = %PanelAlarm
@onready var _beacons: Node3D = %Beacons
@onready var _exit_door: Door = %ExitDoor
@onready var _exit_trigger: TriggerZone = %ExitTrigger

var _found := 0
var _inserted := 0
var _collar_on := false
var _caught := false


func _ready() -> void:
	ProceduralAudio.preload_sounds([&"growl", &"screech", &"thud", &"glass", &"ring", &"collar",
		&"keycard", &"clang", &"alarm", &"splash_0", &"splash_1", &"splash_2"])
	super()
	_bake_navigation()
	for marker in _patrol_points.get_children():
		_stalker.patrol_points.append((marker as Node3D).global_position)
	_beacons.visible = false
	_panel.prompt_text = Localization.t("PROMPT_INSERT_KEYCARDS", [0, KEYCARDS_NEEDED])
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.player_heartbeat_critical.connect(_on_heart_critical)
	_stalker.player_caught.connect(_on_caught)
	_panel.interacted.connect(_on_panel.unbind(1))
	_exit_trigger.triggered.connect(_on_escaped.unbind(1))
	_intro()


## CSG geometry is only built at the end of the first frame, so wait for it.
func _bake_navigation() -> void:
	await get_tree().process_frame
	_navigation.bake_navigation_mesh(false)


func _intro() -> void:
	GameManager.set_state(GameManager.State.CUTSCENE)
	player.set_input_enabled(false)
	await _wait(1.0)
	await _announcer.announce("L2_PA_INTRO")
	EventBus.message_requested.emit(RULES_TITLE, RULES_BODY)
	await EventBus.message_closed
	player.set_input_enabled(false)
	await _announcer.announce("L2_PA_START")
	# Lights out.
	for light: FlickerLight in _house_lights.get_children():
		light.turn_off(false)
	_play_at(_cage_door, &"bang")
	player.add_heartbeat_spike(25.0)
	await _wait(2.0)
	# Something is let out.
	create_tween().tween_property(_cage_door, "rotation_degrees:y", 115.0, 0.5).set_trans(Tween.TRANS_BACK)
	_play_at(_cage_door, &"clang")
	_stalker.release()
	player.get_flashlight().available = true
	start_level()
	player.set_input_enabled(true)
	EventBus.subtitle_requested.emit("L2_SAY_BREATHING", 4.0)
	_update_objective()


# =========================================================================
# Events
# =========================================================================

func _on_timeline_event(event_id: StringName) -> void:
	match event_id:
		&"five_minutes":
			_announcer.announce("L2_PA_FIVE_MIN", false)
		&"one_minute":
			_announcer.announce("L2_PA_ONE_MIN", false)
		&"backup_power": # keycard #2: lights flicker back, the Stalker gets faster
			for light: FlickerLight in _house_lights.get_children():
				light.on_energy *= 0.35
				light.turn_on(FlickerLight.Mode.BROKEN)
			_stalker.enrage(1.25)
			_announcer.announce("L2_PA_BACKUP_POWER", false)
			EventBus.subtitle_requested.emit("L2_SAY_FASTER", 3.0)


func _on_item_picked(item_id: StringName) -> void:
	if item_id != &"keycard":
		return
	_found += 1
	player.add_heartbeat_spike(10.0)
	EventBus.subtitle_requested.emit(Localization.t("L2_SAY_KEYCARD", [_found, KEYCARDS_NEEDED]), 2.5)
	if _found == 2:
		trigger_event(&"backup_power")
	_update_objective()


func _on_panel() -> void:
	var inventory := player.get_node(^"ThrowAbility") as ThrowAbility
	var cards := inventory.count(&"keycard")
	if cards == 0:
		EventBus.subtitle_requested.emit("L2_SAY_NEED_KEYCARD", 2.0)
		return
	inventory.take_item(&"keycard", cards)
	for i in cards:
		var lamp := _slot_lights.get_child(_inserted) as MeshInstance3D
		(lamp.material_override as StandardMaterial3D).emission = Color(0.2, 1.0, 0.4)
		(lamp.material_override as StandardMaterial3D).albedo_color = Color(0.2, 1.0, 0.4)
		_inserted += 1
	_play_at(_panel, &"keycard")
	_panel.prompt_text = Localization.t("PROMPT_INSERT_KEYCARDS", [_inserted, KEYCARDS_NEEDED])
	if _inserted >= KEYCARDS_NEEDED:
		_panel.enabled = false
		_start_escape()
	else:
		_update_objective()


## Final keycard: a 30-second alarm that the Stalker cannot ignore.
func _start_escape() -> void:
	trigger_event(&"final_alarm")
	_panel_alarm.play()
	_beacons.visible = true
	for beacon in _beacons.get_children():
		var spin := beacon.create_tween().set_loops()
		spin.tween_property(beacon, "rotation:y", TAU, 1.0).from(0.0)
	_stalker.enrage(1.4)
	_stalker.summon(_panel.global_position)
	_announcer.announce("L2_PA_OVERRIDE", false)
	var remaining := ESCAPE_DELAY
	while remaining > 0.0 and not _caught:
		EventBus.objective_changed.emit(Localization.t("L2_OBJ_SURVIVE", [ceili(remaining)]))
		if int(remaining) % 6 == 0:
			EventBus.noise_emitted.emit(_panel.global_position, 60.0, _panel) # the alarm keeps calling it
		await _wait(1.0)
		remaining -= 1.0
	if _caught:
		return
	_exit_door.open()
	EventBus.objective_changed.emit("L2_OBJ_RUN")


func _on_escaped() -> void:
	if _caught:
		return
	is_running = false
	player.set_input_enabled(false)
	_panel_alarm.stop()
	await _fx.blink_to(1.0, 1.0)
	complete_level()


func _on_heart_critical(critical: bool) -> void:
	_collar_on = critical
	if not critical or _caught or not is_running:
		return
	EventBus.subtitle_requested.emit("L2_SAY_COLLAR", 3.0)
	while _collar_on and not _caught and is_running:
		_play_at(player, &"collar")
		player.make_noise(COLLAR_NOISE, false)
		await _wait(0.9)


func _on_caught() -> void:
	if _caught:
		return
	_caught = true
	_collar_on = false
	player.set_input_enabled(false)
	player.add_heartbeat_spike(80.0)
	_fx.set_blur(2.0)
	await _wait(0.6)
	await _fx.blink_to(1.0, 0.4)
	player.kill("caught")


func _update_objective() -> void:
	if _found < KEYCARDS_NEEDED:
		EventBus.objective_changed.emit(Localization.t("L2_OBJ_FIND", [_found, KEYCARDS_NEEDED]))
	else:
		EventBus.objective_changed.emit("L2_OBJ_INSERT")


func _play_at(target: Node3D, id: StringName) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(id)
	sound.unit_size = 6.0
	sound.max_distance = 60.0
	target.add_child(sound)
	sound.position = Vector3(0.0, 1.5, 0.0)
	sound.finished.connect(sound.queue_free)
	sound.play()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
