class_name TransitionOverlay
extends CanvasLayer
## Waking-up transition for the ending: eyelids, blur and colour fades drawn
## over the whole screen (shaders/waking_up_blink.gdshader), plus an optional
## still image behind them (the real room the player wakes up in).
##
##   var overlay := TransitionOverlay.new()
##   add_child(overlay)
##   await overlay.fade_to_white(2.0)       # the dream dissolves into light
##   overlay.close_eyes()
##   overlay.set_backdrop(preload("res://.../wake_room.jpg"))
##   await overlay.play_wake_up_sequence()  # blink, blink... awake
##   await overlay.fade_to_black(2.0)

const SHADER := preload("res://shaders/waking_up_blink.gdshader")

var blink_progress := 0.0:
	set(value):
		blink_progress = value
		_apply(&"blink_progress", value)
var blur_amount := 0.0:
	set(value):
		blur_amount = value
		_apply(&"blur_amount", value)
var vignette := 0.0:
	set(value):
		vignette = value
		_apply(&"vignette", value)
var fade_color := Color(0, 0, 0, 0):
	set(value):
		fade_color = value
		_apply(&"fade_color", value)

var _backdrop: TextureRect
var _rect: ColorRect
var _caption: Label
var _material: ShaderMaterial


func _ready() -> void:
	layer = 6 # above the HUD, below the death card / scene fades
	_backdrop = TextureRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = false
	add_child(_backdrop)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -140.0
	_caption.offset_bottom = -70.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 26)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.96, 0.9))
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	add_child(_caption)
	for key: StringName in [&"blink_progress", &"blur_amount", &"vignette"]:
		_apply(key, get(key))
	_apply(&"fade_color", fade_color)


## Shows a still image under the eyelids instead of the 3D world.
func set_backdrop(texture: Texture2D) -> void:
	_backdrop.texture = texture
	_backdrop.visible = texture != null


func close_eyes() -> void:
	blink_progress = 1.0


## Tweens any of the overlay properties: blink_progress, blur_amount,
## vignette, fade_color. Await the returned tween to wait for it.
func animate(property: StringName, value: Variant, duration: float,
		trans := Tween.TRANS_SINE, easing := Tween.EASE_IN_OUT) -> Tween:
	var tween := create_tween().set_trans(trans).set_ease(easing)
	tween.tween_property(self, NodePath(property), value, duration)
	return tween


func fade_to_white(duration: float = 2.0, color := Color(1.0, 0.97, 0.9)) -> void:
	await animate(&"fade_color", Color(color, 1.0), duration).finished


func fade_to_black(duration: float = 1.5) -> void:
	await animate(&"fade_color", Color(0, 0, 0, 1), duration).finished


## A line of text over the overlay (the HUD is underneath it). `key` is a
## translation key or plain text.
func show_caption(key: String, duration: float) -> void:
	_caption.text = Localization.t(key)
	var tween := create_tween()
	tween.tween_property(_caption, "modulate:a", 1.0, 0.6)
	tween.tween_interval(maxf(duration - 1.2, 0.1))
	tween.tween_property(_caption, "modulate:a", 0.0, 0.6)
	await tween.finished


## Clears the colour fade (keeps the eyelids where they are).
func clear_fade(duration: float = 0.0) -> void:
	if duration <= 0.0:
		fade_color = Color(fade_color, 0.0)
	else:
		await animate(&"fade_color", Color(fade_color, 0.0), duration).finished


## From shut eyes: they flutter open, close again, open a little more, and
## finally stay open while the blur clears. Groggy, like real waking.
func play_wake_up_sequence() -> void:
	blur_amount = 4.0
	vignette = 0.7
	blink_progress = 1.0
	await _blink(0.55, 1.3)
	await _blink(1.0, 0.25)
	await get_tree().create_timer(0.7).timeout
	await _blink(0.25, 1.1)
	await _blink(0.8, 0.22)
	animate(&"blur_amount", 0.8, 4.0)
	animate(&"vignette", 0.45, 4.0)
	await _blink(0.0, 1.6)


func _blink(value: float, duration: float) -> void:
	await animate(&"blink_progress", value, duration).finished


func _apply(param: StringName, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(param, value)
