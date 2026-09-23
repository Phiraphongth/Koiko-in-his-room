class_name LevelBase
extends Node3D
## Root script for every level scene. Handles player spawning, the countdown
## timer and time-based timeline events, and reports win/lose via EventBus.
## Level scripts extend this and override the `_on_*` virtual methods.

const DEFAULT_PLAYER_PATH := "res://player/player.tscn"

@export var level_id: StringName = &""
## Countdown in seconds. 0 = no timer.
@export var time_limit := 0.0
## Elapsed seconds -> event id, e.g. {180: &"scaffold_collapse"}.
@export var timeline_events: Dictionary[int, StringName] = {}
## false = wait for an intro cutscene to call start_level() manually.
@export var autostart := true
@export var spawn_player := true
@export var player_scene: PackedScene

var player: Player
var elapsed := 0.0
var time_left := 0.0
var is_running := false

var _pending_times: Array[int] = []
var _finished := false
var _last_tick := -1


func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)
	if spawn_player:
		_spawn_player()
	if autostart:
		start_level.call_deferred()


func start_level() -> void:
	if is_running or _finished:
		return
	elapsed = 0.0
	time_left = time_limit
	_pending_times.assign(timeline_events.keys())
	_pending_times.sort()
	is_running = true
	EventBus.level_started.emit(level_id)
	_on_level_started()


func _process(delta: float) -> void:
	if not is_running:
		return
	elapsed += delta
	while not _pending_times.is_empty() and elapsed >= _pending_times[0]:
		trigger_event(timeline_events[_pending_times.pop_front()])
	if time_limit <= 0.0:
		return
	time_left = maxf(time_limit - elapsed, 0.0)
	var whole := ceili(time_left)
	if whole != _last_tick: # emit once per second, not every frame
		_last_tick = whole
		EventBus.level_timer_tick.emit(time_left)
	if time_left <= 0.0:
		_on_time_up()


## Shortens (negative) or extends the countdown — alarms, bonuses.
func add_time(seconds: float) -> void:
	if time_limit <= 0.0:
		return
	time_limit = maxf(time_limit + seconds, elapsed)
	_last_tick = -1 # force the HUD to refresh on the next frame


## Fire a timeline event. Also call this from gameplay (e.g. keycard pickup).
func trigger_event(event_id: StringName) -> void:
	EventBus.timeline_event.emit(event_id)
	_on_timeline_event(event_id)


func complete_level() -> void:
	if _finished:
		return
	_finished = true
	is_running = false
	EventBus.level_completed.emit(level_id)


func fail_level(reason: String) -> void:
	if _finished:
		return
	_finished = true
	is_running = false
	if player:
		player.set_input_enabled(false)
	EventBus.level_failed.emit(level_id, reason)


# --- Virtual hooks ---------------------------------------------------------

func _on_level_started() -> void:
	pass


func _on_timeline_event(_event_id: StringName) -> void:
	pass


func _on_time_up() -> void:
	fail_level("time_out")


func _on_player_died(reason: String) -> void:
	fail_level(reason)


# --- Internal --------------------------------------------------------------

func _spawn_player() -> void:
	player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		var scene: PackedScene = player_scene if player_scene else load(DEFAULT_PLAYER_PATH)
		player = scene.instantiate() as Player
		add_child(player)
	var spawn := get_node_or_null(^"SpawnPoint") as Node3D
	if spawn:
		player.global_position = spawn.global_position
		player.set_facing(spawn.global_rotation.y)
	EventBus.player_spawned.emit(player)
