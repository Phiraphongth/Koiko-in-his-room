class_name DeathCard
extends CanvasLayer
## Full-screen "player eliminated" card shown after a death cutscene, before
## the game hands over to the ending scene. Built in code like the rest of the
## UI; every string is a translation key.
##
##   var card := DeathCard.new()
##   add_child(card)
##   await card.play(&"L2_DEATH_SUIT", &"L2_DEATH_TITLE", &"L2_DEATH_LINE", &"L2_DEATH_WHISPER")

const RED := Color(0.76, 0.07, 0.07)
const BONE := Color(0.88, 0.86, 0.82)

var _grain: ColorRect
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 6
	_rng.randomize()
	var black := ColorRect.new()
	black.color = Color(0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)


## Fades the card in. Await it to wait until it is fully readable.
func play(suit_key: StringName, title_key: StringName, line_key: StringName,
		whisper_key: StringName) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	add_child(box)

	var suit := _line(suit_key, 30, RED.darkened(0.15))
	var title := _line(title_key, 72, RED)
	var line := _line(line_key, 26, BONE)
	var whisper := _line(whisper_key, 19, Color(0.45, 0.43, 0.4))
	box.add_child(suit)
	box.add_child(title)
	box.add_child(_spacer(18))
	box.add_child(line)
	box.add_child(_spacer(4))
	box.add_child(whisper)

	var tween := create_tween()
	tween.tween_property(box, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	await tween.finished
	_flicker(title)


## A dying-bulb flicker on the headline, so the card never feels still.
func _flicker(target: Control) -> void:
	while is_instance_valid(target):
		await get_tree().create_timer(_rng.randf_range(0.8, 2.4)).timeout
		if not is_instance_valid(target):
			return
		for i in _rng.randi_range(2, 4):
			target.modulate.a = _rng.randf_range(0.25, 0.6)
			await get_tree().create_timer(0.04).timeout
			if not is_instance_valid(target):
				return
			target.modulate.a = 1.0
			await get_tree().create_timer(_rng.randf_range(0.03, 0.09)).timeout


func _line(key: StringName, size: int, color: Color) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.shadow_size = 10
	settings.shadow_color = Color(0.3, 0.0, 0.0, 0.45)
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Localization.set_text(label, key)
	return label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
