extends Control
## The opening comic: six panels of the night Kopiko ruined, shown one at a
## time before the first scene. Only New Game plays it; the level select drops
## straight into a level (see GameManager.start_new_game).
##
## The artwork is one sheet (intro_comic.jpg) and each panel is a region of it,
## so the whole cutscene costs a single texture. Click or Space takes the next
## panel early, Esc skips the rest.

const SHEET := "res://scenes/cutscenes/intro_comic.jpg"
const BORDER := 8.0 ## cream frame painted around a panel
const WIDTH_FILL := 0.84 ## most of the screen a panel may take
const HEIGHT_FILL := 0.76
const FADE := 0.38
const DRIFT := 1.045 ## slow push-in over a panel's hold

const PAPER := Color(0.88, 0.86, 0.80)
const DIM := Color(0.30, 0.29, 0.27)

## rect: the panel inside the sheet. hold: seconds before moving on.
## sfx fires `delay` seconds after the panel appears.
const PANELS: Array[Dictionary] = [
	{"rect": Rect2(10, 8, 484, 296), "hold": 4.2, "sfx": &"", "delay": 0.0},
	{"rect": Rect2(505, 8, 488, 296), "hold": 3.8, "sfx": &"creak", "delay": 0.3},
	{"rect": Rect2(1006, 8, 497, 296), "hold": 3.2, "sfx": &"chime", "delay": 0.2},
	{"rect": Rect2(6, 310, 446, 239), "hold": 4.2, "sfx": &"thud", "delay": 0.1},
	{"rect": Rect2(459, 310, 395, 239), "hold": 2.8, "sfx": &"", "delay": 0.0},
	{"rect": Rect2(865, 310, 671, 239), "hold": 4.8, "sfx": &"shift", "delay": 0.2},
]
## The hallucination starts on the last panel, and hands the game over: the
## ambience turns on its second layer there.
const TURN_PANEL := 5

var _sheet: Texture2D
var _card: Control
var _picture: TextureRect
var _shadow: ColorRect
var _dots: HBoxContainer
var _sfx: ProceduralSound
var _noise: ProceduralSound

var _advance := false
var _skipped := false
var _done := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet = load(SHEET)
	_build()
	var ids: Array[StringName] = [&"shutter"]
	for panel: Dictionary in PANELS:
		if panel["sfx"] != &"":
			ids.append(panel["sfx"])
	ProceduralAudio.preload_sounds(ids)
	_play()


# =========================================================================
# Playback
# =========================================================================

func _play() -> void:
	for index in PANELS.size():
		if _skipped:
			break
		await _show(index)
	_finish()


func _show(index: int) -> void:
	var panel: Dictionary = PANELS[index]
	_frame_panel(panel["rect"])
	for i in _dots.get_child_count():
		(_dots.get_child(i) as ColorRect).color = PAPER if i == index else DIM
	if index == TURN_PANEL:
		_noise.play()

	_sfx.play_sound(&"shutter")
	var hold: float = panel["hold"]
	var tween := create_tween().set_parallel()
	tween.tween_property(_card, "modulate:a", 1.0, FADE).from(0.0)
	tween.tween_property(_card, "scale", Vector2.ONE * DRIFT, hold + FADE).from(Vector2.ONE)
	if panel["sfx"] != &"":
		_sound_in(panel["sfx"], panel["delay"])
	await _wait(hold)
	if _skipped:
		return
	await _fade_card_out()


## Lets the panel land before its sound, without holding up the panel itself.
func _sound_in(id: StringName, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not _skipped and not _done:
		_sfx.play_sound(id)


func _fade_card_out() -> void:
	var tween := create_tween()
	tween.tween_property(_card, "modulate:a", 0.0, FADE * 0.6)
	await tween.finished


## Waits, but gives up early when the player clicks ahead or skips.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _advance and not _skipped:
		left -= get_process_delta_time()
		await get_tree().process_frame
	_advance = false


func _finish() -> void:
	if _done:
		return
	_done = true
	GameManager.finish_intro()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if event.is_action_pressed(&"pause"):
		_skipped = true
		_finish()
	elif click or event.is_action_pressed(&"ui_accept"):
		_advance = true
	else:
		return
	get_viewport().set_input_as_handled()


# =========================================================================
# Building
# =========================================================================

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.035, 0.04)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_shadow = ColorRect.new()
	_shadow.color = Color(0, 0, 0, 0.5)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	# One card holds the cream frame and the artwork, so the push-in can scale
	# both together from the centre of the panel.
	_card = ColorRect.new()
	(_card as ColorRect).color = PAPER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	add_child(_card)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.offset_left = BORDER
	_picture.offset_top = BORDER
	_picture.offset_right = -BORDER
	_picture.offset_bottom = -BORDER
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_picture)

	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 7)
	_dots.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dots)
	for i in PANELS.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(9, 5)
		dot.color = DIM
		_dots.add_child(dot)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.52, 0.51, 0.48))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The text has to be in place first: the corner anchor is measured from the
	# label's own size, which is zero while it is still empty.
	Localization.set_text(hint, &"INTRO_HINT")
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 22)
	add_child(hint)

	_sfx = ProceduralSound.new()
	_sfx.audio_bus = "SFX"
	add_child(_sfx)
	_noise = ProceduralSound.new()
	_noise.sound_id = &"static"
	_noise.audio_bus = "BGM"
	_noise.volume_db = -26.0
	add_child(_noise)
	var ambience := ProceduralSound.new()
	ambience.sound_id = &"drone"
	ambience.audio_bus = "BGM"
	ambience.volume_db = -14.0
	ambience.play_on_ready = true
	add_child(ambience)


## Sizes the card to the panel and centres it.
func _frame_panel(rect: Rect2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = _sheet
	atlas.region = rect
	_picture.texture = atlas

	var screen := get_viewport_rect().size
	var zoom := minf(screen.x * WIDTH_FILL / rect.size.x, screen.y * HEIGHT_FILL / rect.size.y)
	_card.size = rect.size * zoom + Vector2(BORDER, BORDER) * 2.0
	_card.position = ((screen - _card.size) * 0.5).floor()
	_card.pivot_offset = _card.size * 0.5
	_shadow.size = _card.size
	_shadow.position = _card.position + Vector2(7, 9)
	# The box has not been laid out on the first panel yet, so measure the dots.
	var strip := PANELS.size() * 9.0 + (PANELS.size() - 1) * 7.0
	_dots.position = Vector2((screen.x - strip) * 0.5, screen.y - 34.0)
