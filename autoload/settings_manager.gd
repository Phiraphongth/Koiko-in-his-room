extends Node
## Autoload: SettingsManager.
## Single owner of every user setting: audio (Master / BGM / SFX buses),
## graphics (resolution, window mode, vsync, shadow quality), language
## (TranslationServer) and gameplay (mouse sensitivity), plus level progress.
## Everything is stored in user://settings.cfg via ConfigFile and applied on
## boot, so the rest of the game only reads values or listens to signals.
##
##   SettingsManager.set_value(&"audio", &"sfx_volume", 0.5)
##   SettingsManager.get_value(&"graphics", &"shadow_quality")

signal settings_changed(section: StringName, key: StringName, value: Variant)
signal language_changed(locale: String)

const CONFIG_PATH := "user://settings.cfg"
## Setting key -> audio bus name.
const VOLUME_BUSES: Dictionary[StringName, String] = {
	&"master_volume": "Master", &"bgm_volume": "BGM", &"sfx_volume": "SFX"}
const MIN_VOLUME_DB := -40.0
## Trim applied on top of each slider, so "100%" is a comfortable level rather
## than the loudest the mix can go. Lives here, not in the bus layout, because
## the sliders overwrite the layout's own volumes at startup.
const BUS_HEADROOM_DB: Dictionary[String, float] = {
	"Master": -5.0, "BGM": -3.0, "SFX": -3.0}
## Locale -> name shown in the language switcher.
const LANGUAGES: Dictionary[String, String] = {"en": "English", "th": "ไทย"}
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

enum WindowMode { WINDOWED, FULLSCREEN }
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }

const SHADOW_PRESETS: Dictionary[int, Dictionary] = {
	ShadowQuality.OFF: {"directional": 0, "positional": 0, "filter": RenderingServer.SHADOW_QUALITY_HARD},
	ShadowQuality.LOW: {"directional": 2048, "positional": 2048, "filter": RenderingServer.SHADOW_QUALITY_HARD},
	ShadowQuality.MEDIUM: {"directional": 4096, "positional": 4096, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW},
	ShadowQuality.HIGH: {"directional": 8192, "positional": 8192, "filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH},
}

const DEFAULTS: Dictionary[StringName, Dictionary] = {
	&"audio": {&"master_volume": 0.8, &"bgm_volume": 0.75, &"sfx_volume": 0.8},
	&"graphics": {&"resolution": 2, &"window_mode": WindowMode.WINDOWED, &"vsync": true,
		&"shadow_quality": ShadowQuality.MEDIUM},
	&"language": {&"locale": "en"},
	&"gameplay": {&"mouse_sensitivity": 0.003, &"invert_y": false},
	&"progress": {&"unlocked_levels": 1}, # how many entries of GameManager.LEVEL_ORDER are playable
}

var _config := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


# =========================================================================
# Storage
# =========================================================================

func load_settings() -> void:
	var err := _config.load(CONFIG_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("SettingsManager: could not read %s (%s), using defaults" % [CONFIG_PATH, error_string(err)])
	apply_all()


func save_settings() -> void:
	var err := _config.save(CONFIG_PATH)
	if err != OK:
		push_error("SettingsManager: could not save %s (%s)" % [CONFIG_PATH, error_string(err)])


func get_value(section: StringName, key: StringName) -> Variant:
	return _config.get_value(section, key, DEFAULTS[section][key])


## Stores, applies and saves one setting.
func set_value(section: StringName, key: StringName, value: Variant, save: bool = true) -> void:
	_config.set_value(section, key, value)
	_apply(section, key, value)
	settings_changed.emit(section, key, value)
	if save:
		save_settings()


func reset_to_defaults() -> void:
	for section: StringName in DEFAULTS:
		for key: StringName in DEFAULTS[section]:
			if section != &"progress":
				_config.set_value(section, key, DEFAULTS[section][key])
	apply_all()
	save_settings()


func apply_all() -> void:
	for section: StringName in DEFAULTS:
		for key: StringName in DEFAULTS[section]:
			_apply(section, key, get_value(section, key))


func _apply(section: StringName, key: StringName, value: Variant) -> void:
	match section:
		&"audio":
			_apply_volume(key, value)
		&"graphics":
			_apply_graphics(key, value)
		&"language":
			if key == &"locale":
				TranslationServer.set_locale(value)
				Localization.refresh(get_tree())
				language_changed.emit(value)


# =========================================================================
# Audio
# =========================================================================

## Linear 0..1 slider -> dB on the matching bus (0 mutes the bus).
func _apply_volume(key: StringName, value: Variant) -> void:
	if not VOLUME_BUSES.has(key):
		return
	var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
	if bus < 0:
		push_warning("SettingsManager: audio bus '%s' is missing" % VOLUME_BUSES[key])
		return
	var linear := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(bus, is_zero_approx(linear))
	var headroom: float = BUS_HEADROOM_DB.get(VOLUME_BUSES[key], 0.0)
	AudioServer.set_bus_volume_db(bus, maxf(linear_to_db(linear) + headroom, MIN_VOLUME_DB))


# =========================================================================
# Graphics
# =========================================================================

func _apply_graphics(key: StringName, value: Variant) -> void:
	match key:
		&"resolution", &"window_mode":
			_apply_window()
		&"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		&"shadow_quality":
			_apply_shadows(int(value))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = get_value(&"graphics", &"window_mode")
	if mode == WindowMode.FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size: Vector2i = RESOLUTIONS[clampi(get_value(&"graphics", &"resolution"), 0, RESOLUTIONS.size() - 1)]
	DisplayServer.window_set_size(size)
	# Re-centre on the screen the window is currently on.
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


func _apply_shadows(quality: int) -> void:
	var preset: Dictionary = SHADOW_PRESETS[clampi(quality, 0, ShadowQuality.HIGH)]
	RenderingServer.directional_shadow_atlas_set_size(preset.directional, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(preset.filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(preset.filter)
	var viewport := get_viewport()
	if viewport:
		viewport.positional_shadow_atlas_size = preset.positional


# =========================================================================
# Convenience
# =========================================================================

func get_locale() -> String:
	return get_value(&"language", &"locale")


func set_locale(locale: String) -> void:
	if LANGUAGES.has(locale):
		set_value(&"language", &"locale", locale)


## Switches between the two supported languages (used by the quick toggle).
func toggle_language() -> void:
	var locales := LANGUAGES.keys()
	var index := locales.find(get_locale())
	set_locale(locales[(index + 1) % locales.size()])


func get_mouse_sensitivity() -> float:
	return get_value(&"gameplay", &"mouse_sensitivity")


func get_unlocked_levels() -> int:
	return get_value(&"progress", &"unlocked_levels")


## Called by GameManager when a level is cleared.
func unlock_level(count: int) -> void:
	if count > get_unlocked_levels():
		set_value(&"progress", &"unlocked_levels", count)
