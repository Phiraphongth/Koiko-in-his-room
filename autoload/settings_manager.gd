extends Node
## Autoload: SettingsManager.
## Single owner of every user setting: audio (Master / BGM / SFX buses),
## graphics (resolution, 3D render scale, window mode, vsync, shadow quality), language
## (TranslationServer) and gameplay (mouse sensitivity), plus level progress.
## Everything is stored in user://settings.cfg via ConfigFile and applied on
## boot, so the rest of the game only reads values or listens to signals.
##
##   SettingsManager.set_value(&"audio", &"sfx_volume", 0.5)
##   SettingsManager.get_value(&"graphics", &"shadow_quality")
##
## Web (itch.io) build: the browser owns the canvas size, so "resolution" there
## means the 3D render scale (RENDER_SCALES). Window size / vsync are skipped,
## shadow maps are smaller, and Forward+-only effects get a fog fallback
## (see _adapt_environment) whenever the Compatibility renderer is running.

signal settings_changed(section: StringName, key: StringName, value: Variant)
signal language_changed(locale: String)

const CONFIG_PATH := "user://settings.cfg"
## Setting key -> audio bus name.
const VOLUME_BUSES: Dictionary[StringName, String] = {
	&"master_volume": "Master", &"bgm_volume": "BGM", &"sfx_volume": "SFX"}
const MIN_VOLUME_DB := -40.0
## Locale -> name shown in the language switcher.
const LANGUAGES: Dictionary[String, String] = {"en": "English", "th": "ไทย"}
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
## 3D resolution as a fraction of the window/canvas. UI is always drawn at full size.
const RENDER_SCALES: Array[float] = [0.5, 0.67, 0.75, 0.85, 1.0]
const RENDER_SCALE_DEFAULT_DESKTOP := 4 # 100%
const RENDER_SCALE_DEFAULT_WEB := 2 # 75% - keeps integrated GPUs / laptops smooth in the browser

## True when running the HTML5 export (itch.io, browser).
var is_web := OS.has_feature("web")

enum WindowMode { WINDOWED, FULLSCREEN }
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }

## Browsers (WebGL 2) get smaller shadow maps: big atlases cost a lot of VRAM there.
const WEB_SHADOW_PRESETS: Dictionary[int, Dictionary] = {
	ShadowQuality.OFF: {"directional": 0, "positional": 0, "filter": RenderingServer.SHADOW_QUALITY_HARD},
	ShadowQuality.LOW: {"directional": 1024, "positional": 1024, "filter": RenderingServer.SHADOW_QUALITY_HARD},
	ShadowQuality.MEDIUM: {"directional": 2048, "positional": 2048, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW},
	ShadowQuality.HIGH: {"directional": 4096, "positional": 4096, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW},
}

const SHADOW_PRESETS: Dictionary[int, Dictionary] = {
	ShadowQuality.OFF: {"directional": 0, "positional": 0, "filter": RenderingServer.SHADOW_QUALITY_HARD},
	ShadowQuality.LOW: {"directional": 2048, "positional": 2048, "filter": RenderingServer.SHADOW_QUALITY_HARD},
	ShadowQuality.MEDIUM: {"directional": 4096, "positional": 4096, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW},
	ShadowQuality.HIGH: {"directional": 8192, "positional": 8192, "filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH},
}

const DEFAULTS: Dictionary[StringName, Dictionary] = {
	&"audio": {&"master_volume": 0.9, &"bgm_volume": 0.8, &"sfx_volume": 1.0},
	&"graphics": {&"resolution": 2, &"render_scale": RENDER_SCALE_DEFAULT_DESKTOP,
		&"window_mode": WindowMode.WINDOWED, &"vsync": true, &"shadow_quality": ShadowQuality.MEDIUM},
	&"language": {&"locale": "en"},
	&"gameplay": {&"mouse_sensitivity": 0.003, &"invert_y": false},
	&"progress": {&"unlocked_levels": 1}, # how many entries of GameManager.LEVEL_ORDER are playable
}

## Volumetric density -> distance-fog density. Distance fog has no light
## scattering, so it reads thinner; tune here if levels look too clear / murky.
const WEB_FOG_DENSITY_FACTOR := 1.4

var _config := ConfigFile.new()
var _booted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	# Every scene brings its own WorldEnvironment; adapt each one as it enters the tree.
	get_tree().node_added.connect(_on_node_added)


# =========================================================================
# Storage
# =========================================================================

func load_settings() -> void:
	var err := _config.load(CONFIG_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("SettingsManager: could not read %s (%s), using defaults" % [CONFIG_PATH, error_string(err)])
	apply_all()
	_booted = true


func save_settings() -> void:
	var err := _config.save(CONFIG_PATH)
	if err != OK:
		push_error("SettingsManager: could not save %s (%s)" % [CONFIG_PATH, error_string(err)])


func get_value(section: StringName, key: StringName) -> Variant:
	return _config.get_value(section, key, get_default(section, key))


## Platform-aware default (the web build starts at a lower 3D render scale).
func get_default(section: StringName, key: StringName) -> Variant:
	if is_web and section == &"graphics" and key == &"render_scale":
		return RENDER_SCALE_DEFAULT_WEB
	return DEFAULTS[section][key]


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
				_config.set_value(section, key, get_default(section, key))
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
	AudioServer.set_bus_volume_db(bus, maxf(linear_to_db(linear), MIN_VOLUME_DB))


# =========================================================================
# Graphics
# =========================================================================

func _apply_graphics(key: StringName, value: Variant) -> void:
	match key:
		&"resolution", &"window_mode":
			_apply_window()
		&"render_scale":
			_apply_render_scale(int(value))
		&"vsync":
			if not is_web: # the browser always syncs to the display
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		&"shadow_quality":
			_apply_shadows(int(value))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = get_value(&"graphics", &"window_mode")
	if is_web:
		# The page sizes the canvas. Fullscreen only works from a click, so it is
		# never forced at boot - only when the player picks it in Settings.
		if mode == WindowMode.FULLSCREEN and _booted:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif mode == WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		return
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


func _apply_render_scale(index: int) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var scale: float = RENDER_SCALES[clampi(index, 0, RENDER_SCALES.size() - 1)]
	if is_web:
		# High-DPI screens (Retina, phones) report 2-3x the CSS pixels; render 3D
		# against CSS pixels instead so a fullscreen canvas stays affordable.
		scale /= maxf(DisplayServer.screen_get_scale(), 1.0)
	tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR # the only mode Compatibility supports
	tree.root.scaling_3d_scale = clampf(scale, 0.25, 1.0)


func _apply_shadows(quality: int) -> void:
	var presets: Dictionary[int, Dictionary] = WEB_SHADOW_PRESETS if is_web else SHADOW_PRESETS
	var preset: Dictionary = presets[clampi(quality, 0, ShadowQuality.HIGH)]
	RenderingServer.directional_shadow_atlas_set_size(preset.directional, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(preset.filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(preset.filter)
	var viewport := get_viewport()
	if viewport:
		viewport.positional_shadow_atlas_size = preset.positional


# =========================================================================
# Renderer fallback
# =========================================================================

## True when running the Compatibility (OpenGL / WebGL 2) renderer - always the
## case on the web, and the project default so the editor shows the web look.
func is_compatibility_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_adapt_environment.call_deferred(node)


## Compatibility has no volumetric fog, SSAO or SSR. The levels lean on volumetric
## fog for their mood, so swap it for regular distance fog in a dark tint. On
## Forward+ nothing changes, so switching the renderer back restores the original.
func _adapt_environment(world: WorldEnvironment) -> void:
	if not is_instance_valid(world) or world.environment == null or not is_compatibility_renderer():
		return
	var env := world.environment
	if env.has_meta(&"web_adapted") or not env.volumetric_fog_enabled:
		return
	env = env.duplicate() # do not touch the shared scene resource
	env.set_meta(&"web_adapted", true)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = env.volumetric_fog_density * WEB_FOG_DENSITY_FACTOR
	env.fog_light_color = env.ambient_light_color.darkened(0.35)
	env.fog_light_energy = 1.0
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0
	world.environment = env


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
