class_name CardUI
extends CanvasLayer
## Reigns / Inscryption style interface for The Warden's Game.
## Top: FOOD / POWER / MORALE / THREAT meters (hovering a choice previews
## which meters it will move). Left: the other players. Center: the card.
## Keys 1-6 pick an option; Space / Enter continues.

const PAPER := Color(0.86, 0.83, 0.75)
const INK := Color(0.12, 0.1, 0.09)
const BLOOD := Color(0.62, 0.06, 0.05)
const GOOD := Color(0.45, 0.85, 0.5)
const BAD := Color(0.95, 0.3, 0.25)
const SEGMENTS := 10

var _game: WardenGame
var _root: Control
var _day_label: Label
var _meters: Dictionary[StringName, Dictionary] = {} # resource -> {segments, arrow}
var _npc_box: VBoxContainer
var _card: PanelContainer
var _suit: Label
var _title: Label
var _body: Label
var _options: VBoxContainer
var _outcome: RichTextLabel
var _continue: Button
var _showing_outcome := false
var _option_count := 0
var _blink_tweens: Dictionary[StringName, Tween] = {}


func _ready() -> void:
	layer = 20
	_build()
	_root.visible = false


func bind_game(game: WardenGame) -> void:
	_game = game
	game.resources_changed.connect(_update_meters)
	game.npcs_changed.connect(_update_npcs)
	game.phase_changed.connect(_on_phase)
	game.card_presented.connect(_show_card)
	game.outcome_presented.connect(_show_outcome)


func open() -> void:
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.6)


func close() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: _root.visible = false)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if _showing_outcome and (key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER):
		_on_continue()
		get_viewport().set_input_as_handled()
	elif not _showing_outcome and key >= KEY_1 and key < KEY_1 + _option_count:
		var button := _options.get_child(key - KEY_1) as Button
		if button and not button.disabled:
			_on_option(key - KEY_1)
		get_viewport().set_input_as_handled()


# =========================================================================
# Game -> UI
# =========================================================================

func _on_phase(day: int, is_night: bool) -> void:
	_day_label.text = "DAY %d / %d   ·   %s" % [day, WardenGame.DAYS, "NIGHT" if is_night else "DAY"]


func _update_meters(resources: Dictionary) -> void:
	for resource: StringName in _meters:
		var value: int = resources[resource]
		var danger := value >= 8 if resource == &"threat" else value <= 2
		var fill := BAD if resource == &"threat" or danger else Color(0.92, 0.9, 0.85)
		var segments: Array = _meters[resource].segments
		for i in SEGMENTS:
			(segments[i] as ColorRect).color = fill if i < value else Color(1, 1, 1, 0.08)
		_set_blinking(resource, danger)


func _update_npcs(npcs: Array) -> void:
	for child in _npc_box.get_children():
		child.queue_free()
	for npc: WardenNPC in npcs:
		_npc_box.add_child(_npc_panel(npc))


func _show_card(card: Dictionary) -> void:
	_showing_outcome = false
	_suit.text = card.suit
	_suit.label_settings.font_color = BLOOD if card.suit.begins_with("♦") else INK
	_title.text = card.title
	_body.text = card.text
	_body.visible = true
	_outcome.visible = false
	_continue.visible = false
	for child in _options.get_children():
		child.queue_free()
	var options: Array = card.options
	_option_count = options.size()
	for i in options.size():
		var option: Dictionary = options[i]
		var button := _option_button("%d.  %s" % [i + 1, option.label], option.get("detail", ""))
		button.disabled = option.get("disabled", false)
		button.pressed.connect(_on_option.bind(i))
		button.mouse_entered.connect(_preview.bind(option.get("preview", {})))
		button.mouse_exited.connect(_preview.bind({}))
		_options.add_child(button)
	_options.visible = true
	_animate_card()


func _show_outcome(outcome: Dictionary) -> void:
	_showing_outcome = true
	_preview({})
	_title.text = outcome.title
	_body.visible = false
	_options.visible = false
	var lines: PackedStringArray = [outcome.text, ""]
	var deltas: Dictionary = outcome.deltas
	for resource: StringName in deltas:
		var delta: int = deltas[resource]
		var good := delta < 0 if resource == &"threat" else delta > 0
		lines.append("[color=#%s]%s  %s%d[/color]" % [(GOOD if good else BAD).to_html(false),
			WardenGame.RESOURCE_LABELS[resource], "+" if delta > 0 else "", delta])
	for note: String in outcome.notes:
		lines.append("[color=#6b5f55][font_size=14]%s[/font_size][/color]" % note)
	_outcome.text = "\n".join(lines)
	_outcome.visible = true
	_continue.visible = true
	_animate_card()


# =========================================================================
# UI -> Game
# =========================================================================

func _on_option(index: int) -> void:
	if _showing_outcome or _game == null:
		return
	_game.choose(index)


func _on_continue() -> void:
	if not _showing_outcome or _game == null:
		return
	_showing_outcome = false
	_game.advance()


func _preview(preview: Dictionary) -> void:
	for resource: StringName in _meters:
		var arrow: Label = _meters[resource].arrow
		if not preview.has(resource):
			arrow.text = ""
			continue
		var value: int = preview[resource]
		arrow.text = "▲" if value > 0 else ("▼" if value < 0 else "•")
		var good := value < 0 if resource == &"threat" else value > 0
		arrow.label_settings.font_color = GOOD if good else BAD


# =========================================================================
# Construction
# =========================================================================

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Top bar: day + meters.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 34)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(top, Vector4(0.0, 0.02, 1.0, 0.1))
	_root.add_child(top)
	_day_label = _label(18, Color(0.85, 0.2, 0.15))
	top.add_child(_day_label)
	for resource: StringName in WardenGame.RESOURCE_LABELS:
		top.add_child(_meter(resource))

	# Left: the other players.
	_npc_box = VBoxContainer.new()
	_npc_box.add_theme_constant_override("separation", 10)
	_place(_npc_box, Vector4(0.012, 0.14, 0.2, 0.95))
	_root.add_child(_npc_box)

	# Center: the card.
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Card on the right third, so the table and the players stay visible in the middle.
	_place(center, Vector4(0.6, 0.12, 0.99, 0.99))
	_root.add_child(center)
	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color(0.25, 0.05, 0.04)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 18
	_card.add_theme_stylebox_override("panel", style)
	_card.custom_minimum_size = Vector2(440, 0)
	center.add_child(_card)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_card.add_child(vbox)
	_suit = _label(40, BLOOD)
	_suit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_suit)
	_title = _label(22, INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)
	vbox.add_child(HSeparator.new())
	_body = _label(17, INK)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(_body)
	_outcome = RichTextLabel.new()
	_outcome.bbcode_enabled = true
	_outcome.fit_content = true
	_outcome.scroll_active = false
	_outcome.custom_minimum_size = Vector2(400, 0)
	_outcome.add_theme_color_override("default_color", INK)
	_outcome.add_theme_font_size_override("normal_font_size", 17)
	vbox.add_child(_outcome)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	vbox.add_child(_options)
	_continue = _option_button("Continue   [Space]", "")
	_continue.pressed.connect(_on_continue)
	vbox.add_child(_continue)


func _meter(resource: StringName) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	header.add_child(_label(13, Color(0.75, 0.73, 0.7), WardenGame.RESOURCE_LABELS[resource]))
	var arrow := _label(14, GOOD)
	header.add_child(arrow)
	box.add_child(header)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	var segments: Array[ColorRect] = []
	for i in SEGMENTS:
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(11, 12)
		bar.add_child(segment)
		segments.append(segment)
	box.add_child(bar)
	_meters[resource] = {"segments": segments, "arrow": arrow, "bar": bar}
	return box


func _npc_panel(npc: WardenNPC) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.8)
	style.border_width_left = 3
	style.border_color = npc.color
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)
	vbox.add_child(_label(17, npc.color.lightened(0.3), npc.name if npc.alive else "✕  " + npc.name))
	vbox.add_child(_label(12, Color(0.6, 0.58, 0.55), npc.demeanor()))
	if npc.alive:
		for stat: StringName in WardenNPC.STAT_LABELS:
			var row := HBoxContainer.new()
			var name_label := _label(11, Color(0.7, 0.7, 0.7), WardenNPC.STAT_LABELS[stat])
			name_label.custom_minimum_size = Vector2(78, 0)
			row.add_child(name_label)
			var bar := ProgressBar.new()
			bar.max_value = 10
			bar.value = npc.get(stat)
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(90, 7)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.add_theme_stylebox_override("background", _flat_box(Color(1, 1, 1, 0.08)))
			bar.add_theme_stylebox_override("fill", _flat_box(npc.color if stat == &"trust" else Color(0.8, 0.78, 0.74)))
			row.add_child(bar)
			vbox.add_child(row)
	else:
		panel.modulate = Color(1, 1, 1, 0.45)
	return panel


func _option_button(text: String, detail: String) -> Button:
	var button := Button.new()
	button.text = text + ("    — " + detail if detail != "" else "")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _flat_box(Color(0.14, 0.11, 0.1), 10))
	button.add_theme_stylebox_override("hover", _flat_box(Color(0.5, 0.07, 0.05), 10))
	button.add_theme_stylebox_override("pressed", _flat_box(Color(0.35, 0.04, 0.03), 10))
	button.add_theme_stylebox_override("disabled", _flat_box(Color(0.55, 0.52, 0.47), 10))
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.3, 0.28, 0.25))
	return button


func _animate_card() -> void:
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.94, 0.94)
	_card.modulate.a = 0.0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.35)
	tween.tween_property(_card, "modulate:a", 1.0, 0.25)


func _set_blinking(resource: StringName, blinking: bool) -> void:
	var bar: Control = _meters[resource].bar
	if _blink_tweens.has(resource):
		_blink_tweens[resource].kill()
		_blink_tweens.erase(resource)
	bar.modulate.a = 1.0
	if blinking:
		var tween := create_tween().set_loops()
		tween.tween_property(bar, "modulate:a", 0.35, 0.4)
		tween.tween_property(bar, "modulate:a", 1.0, 0.4)
		_blink_tweens[resource] = tween


func _label(size: int, color: Color, text: String = "") -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	label.label_settings = settings
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _flat_box(color: Color, margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.set_content_margin_all(margin)
	return style


func _place(control: Control, anchors: Vector4) -> void:
	control.anchor_left = anchors.x
	control.anchor_top = anchors.y
	control.anchor_right = anchors.z
	control.anchor_bottom = anchors.w
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0
