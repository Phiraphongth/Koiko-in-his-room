extends Node3D
## Title screen: slowly drifting 3D view of the room, four buttons, and the
## Settings / Level Select panels. Scene geometry and UI layout are generated
## by tools/scene_builder/build_main_menu.gd.
##
## Flow: MainMenu -> (Start) hub / (Level Select) any unlocked level.

const CAMERA_PAN_TIME := 26.0
const PANEL_FADE := 0.22
## TEMP (playtest): levels selectable even when still locked. Empty this to restore normal progression.
const PLAYTEST_UNLOCKED: Array[StringName] = [&"level_4"]

@onready var _camera: Camera3D = %BackgroundCamera
@onready var _buttons: VBoxContainer = %Buttons
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _level_select: PanelContainer = %LevelSelect
@onready var _level_list: VBoxContainer = %LevelList
@onready var _start_button: Button = %StartButton
@onready var _level_button: Button = %LevelSelectButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _back_button: Button = %LevelSelectBack

var _busy := false
var _buttons_x := 0.0 # anchored layout position, restored after a panel closes


func _ready() -> void:
	GameManager.set_state(GameManager.State.MENU)
	_settings_panel.visible = false
	_level_select.visible = false
	_start_button.pressed.connect(_on_start)
	_level_button.pressed.connect(func() -> void: _show_panel(_level_select))
	_settings_button.pressed.connect(func() -> void: _show_panel(_settings_panel))
	_quit_button.pressed.connect(_on_quit)
	_quit_button.visible = not SettingsManager.is_web # a browser tab cannot be quit from the game
	_back_button.pressed.connect(_close_panels)
	_settings_panel.closed.connect(_close_panels)
	SettingsManager.language_changed.connect(func(_locale: String) -> void: _build_level_list())
	_build_level_list()
	_buttons_x = _buttons.position.x
	_pan_camera()
	SceneTransition.fade_in(1.2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and (_settings_panel.visible or _level_select.visible):
		_close_panels()
		get_viewport().set_input_as_handled()


# =========================================================================
# Buttons
# =========================================================================

func _on_start() -> void:
	if _busy:
		return
	_busy = true
	await SceneTransition.fade_out(0.8)
	GameManager.start_new_game()


func _on_level(level_id: StringName) -> void:
	if _busy:
		return
	_busy = true
	await SceneTransition.fade_out(0.8)
	GameManager.go_to_level(level_id)


func _on_quit() -> void:
	if _busy:
		return
	_busy = true
	await SceneTransition.fade_out(0.6)
	get_tree().quit()


## One entry per level; everything past the player's progress stays locked.
func _build_level_list() -> void:
	for child in _level_list.get_children():
		child.queue_free()
	var unlocked := SettingsManager.get_unlocked_levels()
	for index in GameManager.LEVEL_ORDER.size():
		var level_id := GameManager.LEVEL_ORDER[index]
		var button := BloodButton.new()
		button.custom_minimum_size = Vector2(340, 38)
		button.add_theme_font_size_override("font_size", 17)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if index < unlocked or level_id in PLAYTEST_UNLOCKED:
			Localization.set_text(button, GameManager.LEVEL_NAME_KEYS[level_id])
			button.pressed.connect(_on_level.bind(level_id))
		else:
			button.disabled = true
			Localization.set_text(button, &"COMMON_LOCKED")
		_level_list.add_child(button)


# =========================================================================
# Transitions
# =========================================================================

func _show_panel(panel: Control) -> void:
	panel.visible = true
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.97, 0.97)
	panel.pivot_offset = panel.size * 0.5
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	tween.tween_property(panel, "modulate:a", 1.0, PANEL_FADE)
	tween.tween_property(panel, "scale", Vector2.ONE, PANEL_FADE)
	tween.tween_property(_buttons, "modulate:a", 0.0, PANEL_FADE)
	tween.tween_property(_buttons, "position:x", _buttons_x - 40.0, PANEL_FADE)
	_buttons.set_deferred(&"visible", false)


func _close_panels() -> void:
	_buttons.visible = true
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	for panel: Control in [_settings_panel, _level_select]:
		if panel.visible:
			tween.tween_property(panel, "modulate:a", 0.0, PANEL_FADE)
			tween.chain().tween_callback(func() -> void: panel.visible = false)
	tween.tween_property(_buttons, "modulate:a", 1.0, PANEL_FADE)
	tween.tween_property(_buttons, "position:x", _buttons_x, PANEL_FADE)


## Endless slow drift, so the title screen never sits still.
func _pan_camera() -> void:
	var start := _camera.transform
	var end := start.translated_local(Vector3(0.9, 0.15, -1.1)).rotated_local(Vector3.UP, deg_to_rad(-7.0))
	var tween := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "transform", end, CAMERA_PAN_TIME)
	tween.tween_property(_camera, "transform", start, CAMERA_PAN_TIME)
