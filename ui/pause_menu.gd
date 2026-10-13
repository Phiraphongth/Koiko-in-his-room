class_name PauseMenu
extends CanvasLayer
## Esc during a level: dim the game and offer Resume / Settings / Main menu /
## Quit. GameManager owns one instance for the whole game, so levels do not
## have to carry their own copy. Runs while the tree is paused.

const ACCENT := Color(0.9, 0.12, 0.1)
const TEXT := Color(0.85, 0.84, 0.8)
const MUTED := Color(0.55, 0.54, 0.5)
const BUTTON_WIDTH := 320

var _box: VBoxContainer
var _settings: SettingsPanel
var _busy := false


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func open() -> void:
	visible = true
	_busy = false
	_show_settings(false)


func close() -> void:
	visible = false
	_show_settings(false)


# =========================================================================
# Input
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"pause"):
		return
	# Esc backs out of the settings first, and only then out of the pause menu.
	if _settings.visible:
		_show_settings(false)
	else:
		GameManager.resume()
	get_viewport().set_input_as_handled()


# =========================================================================
# Buttons
# =========================================================================

func _on_settings() -> void:
	_show_settings(true)


func _on_return_to_menu() -> void:
	if _busy:
		return
	_busy = true
	close()
	GameManager.resume() # lift the pause before the fade so it can animate
	await SceneTransition.fade_out(0.6)
	GameManager.return_to_menu()


func _on_quit() -> void:
	if _busy:
		return
	_busy = true
	await SceneTransition.fade_out(0.6)
	get_tree().quit()


func _show_settings(shown: bool) -> void:
	_settings.visible = shown
	_box.visible = not shown


# =========================================================================
# Building
# =========================================================================

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# The two full-screen containers must not eat the clicks meant for the
	# buttons inside them: IGNORE hides the container from the mouse, not its
	# children. Without this the settings container (added last, so on top)
	# swallows every click even while it is empty.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	center.add_child(_box)

	_box.add_child(_label(&"PAUSE_TITLE", 34, ACCENT))
	_box.add_child(_label(&"PAUSE_HINT", 14, MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	_box.add_child(spacer)

	for entry: Array in [[&"MENU_RESUME", GameManager.resume], [&"MENU_SETTINGS", _on_settings],
			[&"MENU_RETURN_TO_MENU", _on_return_to_menu], [&"MENU_QUIT", _on_quit]]:
		var button := _button(entry[0])
		button.pressed.connect(entry[1])
		_box.add_child(button)

	var settings_center := CenterContainer.new()
	settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(settings_center)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void: _show_settings(false))
	settings_center.add_child(_settings)

	visible = false


func _label(key: StringName, size: int, color: Color) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = 5
	settings.outline_color = Color(0, 0, 0, 0.85)
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Localization.set_text(label, key)
	return label


## Same look as the main menu: dark plate with a crimson edge that lights up.
func _button(key: StringName) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color(0.05, 0.05, 0.06, 0.8), Color(0.35, 0.05, 0.04)))
	button.add_theme_stylebox_override("hover", _style(Color(0.35, 0.04, 0.03, 0.9), ACCENT))
	button.add_theme_stylebox_override("pressed", _style(Color(0.2, 0.02, 0.02, 0.9), ACCENT))
	button.add_theme_stylebox_override("focus", _style(Color(0.1, 0.05, 0.05, 0.6), ACCENT))
	Localization.set_text(button, key)
	return button


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 4
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
