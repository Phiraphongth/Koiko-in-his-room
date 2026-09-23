extends LevelBase
## Level 3 director: "Vertical Abyss" (♠ 5). 10-minute timer.
##
## A 40 m indoor climbing shaft with acid rising from the bottom. Three zones:
## parkour ledges and a wall run, then neon climbing panels (the orange ones
## tear out three seconds after you grab them), then swing bars across the
## shaft and a final dyno jump to the roof.
## 03:00 the lower scaffolding drops, 07:00 the main climbing route falls away.
## Geometry: tools/scene_builder/build_level_3.gd.

const ACID_WARNING_DISTANCE := 3.0
const WARNING_INTERVAL := 8.0

@onready var _fx: HorrorFX = %HorrorFX
@onready var _announcer: Announcer = %Announcer
@onready var _acid: AcidPool = %Acid
@onready var _scaffold: Node3D = %Scaffold
@onready var _fragile_panels: Node3D = %FragilePanels
@onready var _exit_door: Door = %ExitDoor
@onready var _exit_trigger: TriggerZone = %ExitTrigger
@onready var _horn: ProceduralSound = %Horn

var _escaped := false
var _last_warning := -100.0


func _ready() -> void:
	ProceduralAudio.preload_sounds([&"acid", &"siren_low", &"bang", &"shutter",
		&"step_0", &"step_1", &"step_2", &"step_3"])
	super()
	_acid.player_submerged.connect(_on_acid)
	_exit_trigger.triggered.connect(_on_exit.unbind(1))
	player.wall_run_enabled = true
	(player.get_node(^"ClimbAbility") as ClimbAbility).enabled = true
	_intro()


func _process(delta: float) -> void:
	super(delta)
	if not is_running:
		return
	_check_acid()


func _intro() -> void:
	GameManager.set_state(GameManager.State.CUTSCENE)
	player.set_input_enabled(false)
	await _wait(1.0)
	await _announcer.announce("L3_PA_INTRO")
	EventBus.message_requested.emit("L3_RULES_TITLE", "L3_RULES_BODY")
	await EventBus.message_closed
	player.set_input_enabled(false)
	await _announcer.announce("L3_PA_START")
	_horn.play()
	_acid.rising = true
	start_level()
	player.set_input_enabled(true)
	player.get_flashlight().available = true
	EventBus.objective_changed.emit("L3_OBJ_CLIMB")
	EventBus.subtitle_requested.emit("L3_SAY_START", 4.0)


# =========================================================================
# Events
# =========================================================================

func _on_timeline_event(event_id: StringName) -> void:
	match event_id:
		&"scaffold_collapse":
			_horn.play()
			_announcer.announce("L3_PA_SCAFFOLD", false)
			EventBus.subtitle_requested.emit("L3_SAY_SCAFFOLD", 4.0)
			player.add_heartbeat_spike(30.0)
			for piece: Node3D in _scaffold.get_children():
				_drop(piece)
		&"holds_fall":
			_horn.play()
			_announcer.announce("L3_PA_HOLDS", false)
			EventBus.subtitle_requested.emit("L3_SAY_HOLDS", 4.0)
			player.add_heartbeat_spike(30.0)
			for panel: ClimbPanel in _fragile_panels.get_children():
				panel.touched() # arms the 3-second fuse on every fragile panel at once


## Everything below is eaten: the platform sinks into the acid and stops colliding.
func _drop(piece: Node3D) -> void:
	for child in piece.find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).set_deferred(&"disabled", true)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(piece, "position:y", piece.position.y - 25.0, 2.5)
	tween.parallel().tween_property(piece, "rotation:z", randf_range(-0.4, 0.4), 2.5)


## Warns when the acid is nearly at the player's feet.
func _check_acid() -> void:
	var distance := player.global_position.y - _acid.surface_height()
	var now := Time.get_ticks_msec() / 1000.0
	if distance < ACID_WARNING_DISTANCE and now - _last_warning > WARNING_INTERVAL:
		_last_warning = now
		player.add_heartbeat_spike(25.0)
		EventBus.subtitle_requested.emit("L3_SAY_ACID_CLOSE", 3.0)


func _on_acid() -> void:
	if _escaped:
		return
	is_running = false
	player.set_input_enabled(false)
	EventBus.subtitle_requested.emit("L3_SAY_ACID_DEATH", 4.0)
	await _fx.blink_to(1.0, 0.8)
	player.kill("acid")


func _on_exit() -> void:
	if _escaped:
		return
	_escaped = true
	is_running = false
	_acid.rising = false
	player.set_input_enabled(false)
	await _fx.blink_to(1.0, 1.0)
	complete_level()


func _on_time_up() -> void:
	# The acid wins: the scaffolding crumbles into it.
	EventBus.subtitle_requested.emit("L3_SAY_TIME_UP", 4.0)
	fail_level("acid")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
