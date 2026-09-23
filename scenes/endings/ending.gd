extends Control
## Placeholder ending screen (good / bad). Any key restarts from the hub.
## The real ending cutscenes come after Level 4.

@export var is_good := false
@export_multiline var body := ""

var _ready_for_input := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)
	var title := _label("", 56, Color(0.85, 0.85, 0.8) if is_good else Color(0.8, 0.08, 0.06))
	Localization.set_text(title, &"ENDING_GOOD_TITLE" if is_good else &"ENDING_BAD_TITLE")
	vbox.add_child(title)
	var body_label := _label("", 20, Color(0.7, 0.7, 0.68))
	Localization.set_text(body_label, body)
	vbox.add_child(body_label)
	var hint := _label("", 16, Color(0.4, 0.4, 0.4))
	Localization.set_text(hint, &"ENDING_PRESS_ANY_KEY")
	vbox.add_child(hint)
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 2.0)
	tween.tween_callback(func() -> void: _ready_for_input = true)


func _input(event: InputEvent) -> void:
	if _ready_for_input and event.is_pressed() and not event.is_echo():
		_ready_for_input = false
		GameManager.return_to_menu()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
