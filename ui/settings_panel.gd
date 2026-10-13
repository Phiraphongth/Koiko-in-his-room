class_name SettingsPanel
extends PanelContainer
## Reusable settings UI (main menu now, pause menu later). Every control
## reads and writes SettingsManager, which owns saving and applying.
## Labels are bound through Localization so they follow the language switch.

signal closed

const ROW_HEIGHT := 34
const LABEL_WIDTH := 240
const CONTROL_WIDTH := 260

var _rows: Array[Dictionary] = [] # {control, keys} for option buttons that need re-translating
var _language_options: OptionButton


func _ready() -> void:
	_build()
	SettingsManager.language_changed.connect(_on_language_changed)


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.93)
	style.border_color = Color(0.6, 0.06, 0.05)
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(26)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(_title(&"SETTINGS_TITLE", 26, Color(0.9, 0.12, 0.1)))

	box.add_child(_title(&"SETTINGS_AUDIO", 17, Color(0.65, 0.65, 0.6)))
	box.add_child(_slider_row(&"SETTINGS_MASTER_VOLUME", &"audio", &"master_volume", 0.0, 1.0, 0.05))
	box.add_child(_slider_row(&"SETTINGS_BGM_VOLUME", &"audio", &"bgm_volume", 0.0, 1.0, 0.05))
	box.add_child(_slider_row(&"SETTINGS_SFX_VOLUME", &"audio", &"sfx_volume", 0.0, 1.0, 0.05))

	box.add_child(_title(&"SETTINGS_GRAPHICS", 17, Color(0.65, 0.65, 0.6)))
	if not SettingsManager.is_web: # in the browser the page decides the canvas size
		var resolutions: Array[StringName] = []
		for size in SettingsManager.RESOLUTIONS:
			resolutions.append(StringName("%d x %d" % [size.x, size.y])) # not translated
		box.add_child(_option_row(&"SETTINGS_RESOLUTION", &"graphics", &"resolution", resolutions, false))
	var scales: Array[StringName] = []
	for scale in SettingsManager.RENDER_SCALES:
		scales.append(StringName("%d%%" % roundi(scale * 100.0))) # not translated
	box.add_child(_option_row(&"SETTINGS_RENDER_SCALE", &"graphics", &"render_scale", scales, false))
	box.add_child(_option_row(&"SETTINGS_WINDOW_MODE", &"graphics", &"window_mode",
		[&"SETTINGS_WINDOWED", &"SETTINGS_FULLSCREEN"]))
	box.add_child(_option_row(&"SETTINGS_SHADOW_QUALITY", &"graphics", &"shadow_quality",
		[&"SETTINGS_SHADOW_OFF", &"SETTINGS_SHADOW_LOW", &"SETTINGS_SHADOW_MEDIUM", &"SETTINGS_SHADOW_HIGH"]))
	if not SettingsManager.is_web: # browsers always vsync
		box.add_child(_toggle_row(&"SETTINGS_VSYNC", &"graphics", &"vsync"))

	box.add_child(_title(&"SETTINGS_GAMEPLAY", 17, Color(0.65, 0.65, 0.6)))
	box.add_child(_slider_row(&"SETTINGS_MOUSE_SENSITIVITY", &"gameplay", &"mouse_sensitivity", 0.001, 0.008, 0.0005))

	var languages: Array[StringName] = []
	for locale: String in SettingsManager.LANGUAGES:
		languages.append(StringName(SettingsManager.LANGUAGES[locale]))
	box.add_child(_language_row(languages))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	var reset := _button(&"SETTINGS_RESET")
	reset.pressed.connect(_on_reset)
	buttons.add_child(reset)
	var back := _button(&"MENU_BACK")
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)


# =========================================================================
# Rows
# =========================================================================

func _slider_row(label_key: StringName, section: StringName, key: StringName, minimum: float, maximum: float, step: float) -> Control:
	var row := _row(label_key)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = SettingsManager.get_value(section, key)
	slider.custom_minimum_size = Vector2(CONTROL_WIDTH - 60, ROW_HEIGHT)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := _label("", 15, Color(0.75, 0.75, 0.7))
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = _percent(slider.value, minimum, maximum)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = _percent(value, minimum, maximum)
		SettingsManager.set_value(section, key, value))
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _option_row(label_key: StringName, section: StringName, key: StringName, item_keys: Array, translate: bool = true) -> Control:
	var row := _row(label_key)
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(CONTROL_WIDTH, ROW_HEIGHT)
	options.fit_to_longest_item = false
	for item_key: StringName in item_keys:
		options.add_item(Localization.t(item_key) if translate else String(item_key))
	options.selected = clampi(int(SettingsManager.get_value(section, key)), 0, item_keys.size() - 1)
	options.item_selected.connect(func(index: int) -> void: SettingsManager.set_value(section, key, index))
	row.add_child(options)
	if translate:
		_rows.append({"control": options, "keys": item_keys})
	return row


func _toggle_row(label_key: StringName, section: StringName, key: StringName) -> Control:
	var row := _row(label_key)
	var toggle := CheckButton.new()
	toggle.button_pressed = SettingsManager.get_value(section, key)
	toggle.custom_minimum_size = Vector2(CONTROL_WIDTH, ROW_HEIGHT)
	toggle.toggled.connect(func(pressed: bool) -> void: SettingsManager.set_value(section, key, pressed))
	row.add_child(toggle)
	return row


func _language_row(names: Array[StringName]) -> Control:
	var row := _row(&"SETTINGS_LANGUAGE")
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(CONTROL_WIDTH, ROW_HEIGHT)
	_language_options = options
	for language_name: StringName in names:
		options.add_item(String(language_name))
	var locales: Array = SettingsManager.LANGUAGES.keys()
	options.selected = maxi(locales.find(SettingsManager.get_locale()), 0)
	options.item_selected.connect(func(index: int) -> void: SettingsManager.set_locale(locales[index]))
	row.add_child(options)
	return row


func _row(label_key: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var label := _label("", 17)
	Localization.set_text(label, label_key)
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


# =========================================================================
# Helpers
# =========================================================================

func _on_language_changed(locale: String) -> void:
	# The language may have been changed elsewhere (quick toggle, another panel).
	var locales: Array = SettingsManager.LANGUAGES.keys()
	_language_options.selected = maxi(locales.find(locale), 0)
	for entry in _rows:
		var options: OptionButton = entry.control
		var selected := options.selected
		options.clear()
		for item_key: StringName in entry.keys:
			options.add_item(Localization.t(item_key))
		options.selected = selected


func _on_reset() -> void:
	SettingsManager.reset_to_defaults()
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_build()


func _percent(value: float, minimum: float, maximum: float) -> String:
	return "%d%%" % roundi(inverse_lerp(minimum, maximum, value) * 100.0)


func _label(text: String, size: int, color: Color = Color(0.92, 0.92, 0.9)) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	label.label_settings = settings
	label.text = text
	return label


func _title(key: StringName, size: int, color: Color) -> Label:
	var label := _label("", size, color)
	Localization.set_text(label, key)
	return label


func _button(key: StringName) -> Button:
	var button := Button.new()
	Localization.set_text(button, key)
	button.custom_minimum_size = Vector2(150, ROW_HEIGHT + 4)
	button.add_theme_font_size_override("font_size", 16)
	return button
