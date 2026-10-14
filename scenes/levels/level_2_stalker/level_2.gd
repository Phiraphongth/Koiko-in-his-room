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
var _heart_stopped := false
var _nav_ready := false


func _ready() -> void:
	ProceduralAudio.preload_sounds([&"growl", &"screech", &"thud", &"glass", &"ring", &"collar",
		&"keycard", &"clang", &"alarm", &"splash_0", &"splash_1", &"splash_2",
		&"crunch", &"flatline", &"gasp", &"bite", &"tear", &"bone_crack"])
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


## Bakes the Stalker's navigation mesh once the CSG geometry exists (it is
## only built at the end of the first frame), then checks the navigation map
## really contains it before the Stalker is let out.
##
## Replaying Level 2 after a death used to leave the Stalker frozen in its
## cage: the NavigationMesh is a sub-resource shared by every load of the scene
## and was re-baked in place while the region was registered with it, so the
## map sometimes kept an empty copy (no paths anywhere). Now each run bakes
## into a brand-new mesh and hands it to the region only when it is complete,
## and re-registers it if the map still comes back empty.
func _bake_navigation() -> void:
	var map := _navigation.get_navigation_map()
	var mesh: NavigationMesh = null
	for attempt in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
		mesh = _navigation.navigation_mesh.duplicate() as NavigationMesh # the settings
		mesh.clear()
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(mesh, source, _navigation)
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		if mesh.get_polygon_count() > 0:
			break # otherwise the CSG is not built yet: try again next frame
	_navigation.navigation_mesh = mesh
	# Wait (up to ~1 s each time) for the server to put it into the map;
	# if it never shows up, register it again.
	for attempt in 3:
		for wait in 60:
			await get_tree().physics_frame
			if _navigation_ready(map):
				_nav_ready = true
				return
		_navigation.navigation_mesh = null
		await get_tree().physics_frame
		_navigation.navigation_mesh = mesh
	push_error("Level 2: the navigation map is still empty, the Stalker cannot move")
	_nav_ready = true # let the level carry on rather than hang the intro


## True when the map can route from the cage to a patrol point.
func _navigation_ready(map: RID) -> bool:
	if _stalker.patrol_points.is_empty():
		return true
	var path := NavigationServer3D.map_get_path(map, _stalker.global_position, _stalker.patrol_points[0], true)
	return path.size() > 1


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
	# Something is let out (once it has somewhere to go).
	while not _nav_ready:
		await get_tree().physics_frame
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
	_panel_alarm.stop()
	_death_sequence()


# =========================================================================
# Death cutscene — "it heard you"
# =========================================================================

## The Stalker takes the camera and eats you (StalkerKillCutscene: it rears up
## and unhinges its jaw, pins you, bites, then drags the body away). Then the
## heart gives out, the game announces the elimination, and only after the
## card does the run officially end (-> bad ending).
func _death_sequence() -> void:
	(get_node(^"HUD") as CanvasLayer).visible = false
	var found_hiding := player.is_hidden
	if found_hiding:
		await _drag_out_of_hiding()
	player.set_input_enabled(false)
	player.set_model_visible(false)
	player.cinematic_camera(true)
	player.cinematic_zoom(0.05, 64.0, 0.35)
	player.cinematic_shake(0.012, 2.4)
	player.add_heartbeat_spike(130.0)
	_play_at(player, &"gasp")
	# The world closes in and drains to red (kept light enough to see its face).
	_fx.lock_effects(true)
	_fx.effect_to(&"vignette", 0.75, 1.6)
	_fx.effect_to(&"aberration", 0.008, 1.6)
	_fx.effect_to(&"grain", 0.13, 1.6)
	_fx.effect_to(&"blur", 0.2, 1.6)
	_fx.tint_to(Color(1.0, 0.75, 0.72), 1.4)
	_last_heartbeats()
	var cutscene := StalkerKillCutscene.new()
	add_child(cutscene)
	await cutscene.play(player, _stalker, _fx)

	# Lights out behind the eyelids.
	_heart_stopped = true
	_fx.set_effect(&"blink", 1.0)
	_fx.set_effect(&"pulse", 0.0)
	await _wait(2.4) # the last three beats play out in the dark
	var card := DeathCard.new()
	add_child(card)
	_announcer.announce("L2_PA_ELIMINATED")
	await card.play(&"L2_DEATH_SUIT", &"L2_DEATH_TITLE", &"L2_DEATH_LINE",
		&"L2_DEATH_WHISPER_HIDING" if found_hiding else &"L2_DEATH_WHISPER")
	await _wait(2.0)
	player.kill("caught")


## Found in a locker: it slams into the door, then rips the player out to stand
## face to face with it. Returns with the player out of hiding and input off.
func _drag_out_of_hiding() -> void:
	var spot := player.current_hide_spot
	var out := Vector3(spot.global_basis.z.x, 0.0, spot.global_basis.z.z).normalized() # the locker's front
	player.add_heartbeat_spike(40.0)
	_play_at(spot, &"slam")
	# The lunge at the door, seen through the vents, and the whole locker shakes.
	var stalker_at := _stalker.global_position
	var lunge := create_tween().set_trans(Tween.TRANS_QUAD)
	lunge.tween_property(_stalker, "global_position", stalker_at - out * 0.35, 0.1).set_ease(Tween.EASE_IN)
	lunge.tween_property(_stalker, "global_position", stalker_at, 0.35).set_ease(Tween.EASE_OUT)
	var view := get_viewport().get_camera_3d()
	if view:
		var shake := create_tween()
		for i in 6:
			shake.tween_property(view, "h_offset", randf_range(-0.05, 0.05), 0.04)
			shake.parallel().tween_property(view, "v_offset", randf_range(-0.04, 0.04), 0.04)
		shake.tween_property(view, "h_offset", 0.0, 0.05)
		shake.parallel().tween_property(view, "v_offset", 0.0, 0.05)
	await _wait(0.6)

	# The yank: out through the door, straight into its face.
	player.set_input_enabled(false) # also leaves the hiding spot
	player.set_model_visible(false)
	player.cinematic_camera(true)
	player.cinematic_zoom(0.05, 64.0, 0.05)
	player.set_facing(atan2(-out.x, -out.z))
	player.global_position = spot.global_position + out * 0.45
	player.cinematic_look_at(_stalker.global_position + Vector3.UP * 1.6, 0.2)
	player.cinematic_shake(0.05, 0.4)
	_play_at(player, &"thud")
	var yank := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	yank.tween_property(player, "global_position", spot.global_position + out * 0.9, 0.25)
	await yank.finished


## Racing while it leans in, then three beats that slow down and stop.
func _last_heartbeats() -> void:
	var beats := _sound(&"heartbeat", 2.0)
	while not _heart_stopped:
		beats.pitch_scale = 1.3
		beats.play()
		await _wait(0.32)
	for i in 3:
		beats.pitch_scale = 0.85 - i * 0.2
		beats.volume_db = 1.0 - i * 4.0
		beats.play()
		await _wait(0.5 + i * 0.3)
	beats.queue_free()
	var tone := _sound(&"flatline", -24.0)
	tone.play()
	create_tween().tween_property(tone, "volume_db", -8.0, 1.2)


func _sound(id: StringName, volume_db: float) -> AudioStreamPlayer:
	var sound := AudioStreamPlayer.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(id)
	sound.volume_db = volume_db
	add_child(sound)
	return sound


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
