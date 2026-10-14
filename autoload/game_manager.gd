extends Node
## Owns the global game state, level progression and ending decision
## (Autoload: GameManager). Levels never load each other; they report
## results through EventBus and GameManager decides what comes next.

enum State { BOOT, MENU, CUTSCENE, PLAYING, PAUSED, GAME_OVER, ENDING, UI }
## UI = gameplay through an on-screen interface (puzzle overlay): mouse visible, pause allowed.

const MAIN_MENU := "res://scenes/menu/main_menu.tscn"
const LEVELS: Dictionary[StringName, String] = {
	&"hub": "res://scenes/hub/hub.tscn",
	&"level_1": "res://scenes/levels/level_1_maze/level_1.tscn",
	&"level_2": "res://scenes/levels/level_2_stalker/level_2.tscn",
	&"level_4": "res://scenes/levels/level_4_valve/level_4.tscn",
}
const LEVEL_ORDER: Array[StringName] = [&"hub", &"level_1", &"level_2", &"level_4"]
## Translation keys shown in the level-select menu (see localization/ui.csv).
const LEVEL_NAME_KEYS: Dictionary[StringName, StringName] = {
	&"hub": &"LEVEL_HUB", &"level_1": &"LEVEL_1", &"level_2": &"LEVEL_2",
	&"level_4": &"LEVEL_4",
}
## The comic that opens a new run (not the level select, which drops straight in).
const INTRO_COMIC := "res://scenes/cutscenes/intro_comic.tscn"
const ENDING_GOOD := "res://scenes/endings/ending_good.tscn"
const ENDING_BAD := "res://scenes/endings/ending_bad.tscn"
## Played after the last level, before the good / bad ending card.
const ENDING_DREAM := "res://scenes/endings/dream/dream_ending.tscn"
const DREAM_LIGHT := Color(1.0, 0.97, 0.9)
const GAME_OVER_DELAY := 2.0

var state: State = State.BOOT
var current_level_id: StringName = &""
var good_ending := false # set by Level 4
## Per-run results levels can record (e.g. who survived Level 1).
var run_data: Dictionary = {}

var _state_before_pause: State = State.PLAYING
var _current_player: Player
var _pause_menu: PauseMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputConfig.register_defaults()
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.level_failed.connect(_on_level_failed)
	EventBus.good_ending_earned.connect(func(earned: bool) -> void: good_ending = earned)
	EventBus.player_spawned.connect(_apply_player_settings)
	SettingsManager.settings_changed.connect(func(section: StringName, _key: StringName, _value: Variant) -> void:
		if section == &"gameplay":
			_apply_player_settings(_current_player))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if state == State.PLAYING or state == State.UI:
		_state_before_pause = state
		set_state(State.PAUSED)
		_open_pause_menu()
	elif state == State.PAUSED and _pause_menu == null:
		set_state(_state_before_pause) # no menu (shouldn't happen): don't trap the player
	get_viewport().set_input_as_handled()


## Closes the pause menu and hands control back to the level.
func resume() -> void:
	if state != State.PAUSED:
		return
	if _pause_menu:
		_pause_menu.close()
	set_state(_state_before_pause)


## The menu lives on the root, so one instance survives every level change.
func _open_pause_menu() -> void:
	if _pause_menu == null:
		_pause_menu = PauseMenu.new()
		get_tree().root.add_child(_pause_menu)
	_pause_menu.open()


## Back to the title screen (from an ending or the pause menu).
func return_to_menu() -> void:
	SceneTransition.set_color(Color.BLACK) # in case the dream's white fade is still set
	set_state(State.MENU)
	LevelLoader.change_level(MAIN_MENU)


func start_new_game() -> void:
	good_ending = false
	run_data.clear()
	current_level_id = &"intro_comic"
	set_state(State.CUTSCENE)
	LevelLoader.change_level(INTRO_COMIC)


## The opening comic is over (or was skipped): into the flat.
func finish_intro() -> void:
	go_to_level(LEVEL_ORDER[0])


func go_to_level(level_id: StringName) -> void:
	if not LEVELS.has(level_id):
		push_error("GameManager: unknown level '%s'" % level_id)
		return
	current_level_id = level_id
	set_state(State.CUTSCENE) # input locked until the level calls start_level()
	LevelLoader.change_level(LEVELS[level_id])


func set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old_state := state
	state = new_state
	get_tree().paused = state == State.PAUSED
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if state == State.PLAYING else Input.MOUSE_MODE_VISIBLE
	EventBus.game_state_changed.emit(state, old_state)


func _on_level_started(level_id: StringName) -> void:
	current_level_id = level_id
	set_state(State.PLAYING)


func _on_level_completed(level_id: StringName) -> void:
	if level_id == LEVEL_ORDER.back():
		_enter_dream()
		return
	var index := LEVEL_ORDER.find(level_id)
	if index == -1:
		push_warning("GameManager: completed level '%s' is not in LEVEL_ORDER" % level_id)
		return
	SettingsManager.unlock_level(index + 2) # the next level is now selectable
	go_to_level(LEVEL_ORDER[index + 1])


func _on_level_failed(_level_id: StringName, _reason: String) -> void:
	set_state(State.GAME_OVER)
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	_trigger_ending(false) # any failure = Bad Ending


## Keeps the player's controls in sync with the gameplay settings.
func _apply_player_settings(player: Node3D) -> void:
	_current_player = player as Player
	if _current_player:
		_current_player.mouse_sensitivity = SettingsManager.get_mouse_sensitivity()


## Final stage cleared: fade to warm white into the ending dream
## (scenes/endings/dream), which calls finish_dream() once the player wakes up.
func _enter_dream() -> void:
	current_level_id = &"dream_ending"
	set_state(State.CUTSCENE)
	SceneTransition.set_color(DREAM_LIGHT)
	LevelLoader.change_level(ENDING_DREAM)


## The player woke up: back to black fades, then the good / bad ending card.
func finish_dream() -> void:
	SceneTransition.set_color(Color.BLACK)
	_trigger_ending(good_ending)


func _trigger_ending(is_good: bool) -> void:
	set_state(State.ENDING)
	EventBus.ending_reached.emit(is_good)
	LevelLoader.change_level(ENDING_GOOD if is_good else ENDING_BAD)
