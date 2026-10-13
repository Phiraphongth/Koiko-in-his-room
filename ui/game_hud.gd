class_name GameHUD
extends CanvasLayer
## In-game UI, driven entirely by EventBus: interaction prompt, subtitles,
## objective, announcement banner, message panel (phone / notes), level
## timer and stamina bar. Kept minimal so the horror atmosphere stays clean.

const RED := Color(0.9, 0.12, 0.1)
const MESSAGE_CLOSE_DELAY_MS := 250
const ITEM_NAMES: Dictionary[StringName, String] = {&"bottle": "ITEM_BOTTLE", &"clock": "ITEM_CLOCK"}

## Level 2 style heart-rate readout (bottom left).
@export var show_heart_monitor := false

var _player: Player
var _hidden_by_pause := false
var _prompt: Label
var _dot: ColorRect
var _subtitle: Label
var _objective_box: VBoxContainer
var _objective: Label
var _banner: PanelContainer
var _banner_label: Label
var _message: CenterContainer
var _message_title: Label
var _message_body: Label
var _timer: Label
var _stamina: ProgressBar
var _heart: Label
var _inventory: Label
var _keycards: Label
var _hidden_overlay: Control
var _message_opened_at := 0
var _subtitle_serial := 0
var _banner_serial := 0


func _ready() -> void:
	layer = 10
	_build()
	EventBus.player_spawned.connect(func(p: Node3D) -> void: _player = p as Player)
	EventBus.interaction_prompt_changed.connect(_on_prompt)
	EventBus.subtitle_requested.connect(show_subtitle)
	EventBus.objective_changed.connect(set_objective)
	EventBus.announcement.connect(show_announcement)
	EventBus.message_requested.connect(show_message)
	EventBus.level_timer_tick.connect(_on_timer)
	EventBus.player_stamina_changed.connect(_on_stamina)
	EventBus.player_heartbeat_changed.connect(_on_heartbeat)
	EventBus.player_hidden_changed.connect(func(hidden: bool) -> void: _hidden_overlay.visible = hidden)
	EventBus.inventory_changed.connect(_on_inventory)
	EventBus.game_state_changed.connect(_on_game_state)


## The HUD gets out of the way while the pause menu is up, and comes back
## only if it was actually on screen before (a death cutscene hides it too).
func _on_game_state(new_state: int, _old_state: int) -> void:
	if new_state == GameManager.State.PAUSED:
		_hidden_by_pause = visible
		visible = false
	elif _hidden_by_pause:
		_hidden_by_pause = false
		visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not _message.visible:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"pause"):
		if Time.get_ticks_msec() - _message_opened_at > MESSAGE_CLOSE_DELAY_MS:
			_close_message()
		get_viewport().set_input_as_handled()


func show_subtitle(text: String, duration: float = 3.0) -> void:
	_subtitle_serial += 1
	var serial := _subtitle_serial
	_subtitle.text = Localization.t(text)
	_fade(_subtitle, 1.0, 0.2)
	await get_tree().create_timer(duration).timeout
	if serial == _subtitle_serial:
		_fade(_subtitle, 0.0, 0.6)


func set_objective(text: String) -> void:
	# A plain key keeps following the language; already-formatted text is shown as-is.
	if Localization.is_key(text):
		Localization.set_text(_objective, text)
	else:
		Localization.clear(_objective)
		_objective.text = text
	_objective_box.visible = text != ""
	_objective_box.modulate.a = 0.0
	_fade(_objective_box, 1.0, 0.8)


func show_announcement(text: String, duration: float = 3.0) -> void:
	_banner_serial += 1
	var serial := _banner_serial
	_banner_label.text = Localization.t(text)
	_banner.visible = true
	_fade(_banner, 1.0, 0.25)
	await get_tree().create_timer(duration).timeout
	if serial == _banner_serial:
		_fade(_banner, 0.0, 0.5)


func show_message(title: String, body: String) -> void:
	_message_title.text = Localization.t(title)
	_message_body.text = Localization.t(body)
	_message.visible = true
	_message_opened_at = Time.get_ticks_msec()
	if _player:
		_player.set_input_enabled(false)


func _close_message() -> void:
	_message.visible = false
	if _player:
		_player.set_input_enabled(true)
	EventBus.message_closed.emit()


func _on_prompt(text: String) -> void:
	_prompt.text = "[E]  " + Localization.t(text) if text != "" else ""
	_dot.color.a = 0.9 if text != "" else 0.35


func _on_timer(time_left: float) -> void:
	_timer.visible = true
	var whole := ceili(time_left)
	_timer.text = "%02d:%02d" % [whole / 60, whole % 60]


func _on_stamina(current: float, maximum: float) -> void:
	_stamina.max_value = maximum
	_stamina.value = current
	_stamina.visible = current < maximum - 0.5


func _on_heartbeat(bpm: float, normalized: float) -> void:
	if not show_heart_monitor:
		return
	_heart.text = "♥  %d BPM" % roundi(bpm)
	_heart.label_settings.font_color = Color.WHITE.lerp(RED, clampf(normalized * 1.6, 0.0, 1.0))


func _on_inventory(items: Dictionary, selected: StringName) -> void:
	var parts: PackedStringArray = []
	for id: StringName in ITEM_NAMES:
		var amount: int = items.get(id, 0)
		if amount > 0:
			parts.append(("▶ " if id == selected else "   ") + "%s ×%d" % [Localization.t(ITEM_NAMES[id]), amount])
	_inventory.text = "\n".join(parts) + ("\n" + Localization.t("HUD_THROW_HINT") if not parts.is_empty() else "")
	var cards: int = items.get(&"keycard", 0)
	_keycards.text = Localization.t("HUD_KEYCARDS", [cards]) if cards > 0 else ""


func _fade(control: CanvasItem, alpha: float, duration: float) -> void:
	create_tween().tween_property(control, "modulate:a", alpha, duration)


# =========================================================================
# Construction
# =========================================================================

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dot = ColorRect.new()
	_dot.color = Color(1, 1, 1, 0.35)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_dot, Vector4(0.5, 0.5, 0.5, 0.5))
	_dot.offset_left = -2
	_dot.offset_top = -2
	_dot.offset_right = 2
	_dot.offset_bottom = 2
	root.add_child(_dot)

	_prompt = _label(20)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, Vector4(0.25, 0.57, 0.75, 0.63))
	root.add_child(_prompt)

	_subtitle = _label(24)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.modulate.a = 0.0
	_place(_subtitle, Vector4(0.1, 0.84, 0.9, 0.96))
	root.add_child(_subtitle)

	_objective_box = VBoxContainer.new()
	_objective_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_box.visible = false
	_place(_objective_box, Vector4(0.03, 0.04, 0.5, 0.2))
	var objective_header := _label(13, Color(0.7, 0.7, 0.7))
	Localization.set_text(objective_header, &"HUD_OBJECTIVE")
	_objective_box.add_child(objective_header)
	_objective = _label(19)
	_objective_box.add_child(_objective)
	root.add_child(_objective_box)

	_timer = _label(44, RED)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer.visible = false
	_place(_timer, Vector4(0.7, 0.03, 0.97, 0.13))
	root.add_child(_timer)

	_stamina = ProgressBar.new()
	_stamina.show_percentage = false
	_stamina.visible = false
	_stamina.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.5)))
	_stamina.add_theme_stylebox_override("fill", _box(Color(1, 1, 1, 0.7)))
	_place(_stamina, Vector4(0.42, 0.93, 0.58, 0.935))
	root.add_child(_stamina)

	_heart = _label(22)
	_heart.visible = show_heart_monitor
	_place(_heart, Vector4(0.03, 0.9, 0.3, 0.97))
	root.add_child(_heart)
	_inventory = _label(16, Color(0.85, 0.85, 0.8))
	_inventory.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inventory.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_place(_inventory, Vector4(0.6, 0.78, 0.97, 0.97))
	root.add_child(_inventory)
	_keycards = _label(18, Color(0.35, 1.0, 0.5))
	_keycards.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_keycards, Vector4(0.6, 0.14, 0.97, 0.2))
	root.add_child(_keycards)

	# Inside a locker: dark with light through horizontal vents.
	_hidden_overlay = Control.new()
	_hidden_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hidden_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hidden_overlay.visible = false
	var slats := VBoxContainer.new()
	slats.set_anchors_preset(Control.PRESET_FULL_RECT)
	slats.add_theme_constant_override("separation", 0)
	slats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hidden_overlay.add_child(slats)
	for i in 14:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.97 if i < 4 or i > 9 or i % 2 == 0 else 0.0)
		bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slats.add_child(bar)
	var hint := _label(16, Color(0.7, 0.7, 0.7))
	Localization.set_text(hint, &"HUD_HIDING_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(hint, Vector4(0.0, 0.93, 1.0, 0.98))
	_hidden_overlay.add_child(hint)
	root.add_child(_hidden_overlay)

	# Announcement banner (top center, red rules above and below).
	var banner_center := CenterContainer.new()
	banner_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(banner_center, Vector4(0.0, 0.07, 1.0, 0.27))
	root.add_child(banner_center)
	_banner = PanelContainer.new()
	var banner_style := _box(Color(0, 0, 0, 0.6))
	banner_style.border_width_top = 2
	banner_style.border_width_bottom = 2
	banner_style.border_color = RED
	banner_style.content_margin_left = 48
	banner_style.content_margin_right = 48
	banner_style.content_margin_top = 14
	banner_style.content_margin_bottom = 14
	_banner.add_theme_stylebox_override("panel", banner_style)
	_banner.visible = false
	_banner.modulate.a = 0.0
	_banner_label = _label(28)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_label)
	banner_center.add_child(_banner)

	# Message panel (phone screen / notes).
	_message = CenterContainer.new()
	_message.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.visible = false
	root.add_child(_message)
	var panel := PanelContainer.new()
	var panel_style := _box(Color(0.02, 0.02, 0.03, 0.93))
	panel_style.border_width_left = 3
	panel_style.border_color = RED
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", panel_style)
	_message.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	_message_title = _label(20, RED)
	vbox.add_child(_message_title)
	_message_body = _label(18, Color(0.92, 0.92, 0.92), "", 0)
	_message_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_body.custom_minimum_size = Vector2(480, 0)
	vbox.add_child(_message_body)
	var close_hint := _label(14, Color(0.55, 0.55, 0.55), "", 0)
	Localization.set_text(close_hint, &"HUD_MESSAGE_CLOSE")
	vbox.add_child(close_hint)


func _label(size: int, color: Color = Color.WHITE, text: String = "", outline: int = 6) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = outline
	settings.outline_color = Color(0, 0, 0, 0.9)
	label.label_settings = settings
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


## anchors = (left, top, right, bottom) as fractions of the screen.
func _place(control: Control, anchors: Vector4) -> void:
	control.anchor_left = anchors.x
	control.anchor_top = anchors.y
	control.anchor_right = anchors.z
	control.anchor_bottom = anchors.w
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0
