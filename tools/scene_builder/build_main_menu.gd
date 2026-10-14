extends SceneBuilder
## Offline tool: generates scenes/menu/main_menu.tscn.
## A dim bedroom seen from the corner (the room Kopiko wakes up in) as a live
## 3D backdrop, plus the title, the four menu buttons and the Settings /
## Level Select panels.

const MENU_SCRIPT := preload("res://scenes/menu/main_menu.gd")
const SETTINGS_PANEL := preload("res://ui/settings_panel.gd")
const BLOOD_BUTTON := preload("res://ui/blood_button.gd")
const TITLE_COLOR := Color(0.92, 0.9, 0.86)
const ACCENT := Color(0.9, 0.12, 0.1)


func _output_path() -> String:
	return "res://scenes/menu/main_menu.tscn"


func _build() -> void:
	_root.name = "MainMenu"
	_root.set_script(MENU_SCRIPT)
	_materials()
	_environment(0.025, Color(0.05, 0.055, 0.075))
	_backdrop()
	_ui()
	var fx := CanvasLayer.new()
	fx.set_script(FX)
	fx.set("base_vignette", 0.45)
	fx.set("heartbeat_audio", false)
	_add(_root, fx, "HorrorFX")
	var ambience := AudioStreamPlayer.new()
	ambience.set_script(SOUND)
	ambience.set("sound_id", &"drone")
	ambience.set("play_on_ready", true)
	ambience.set("audio_bus", "BGM")
	ambience.volume_db = -6.0
	_add(_root, ambience, "Ambience")


func _materials() -> void:
	_m.plaster = _textured(Color(0.22, 0.21, 0.19), Color(0.45, 0.43, 0.39), 0.012, 81, 0.95, Vector3.ONE * 0.4)
	_m.wood = _textured(Color(0.09, 0.055, 0.03), Color(0.25, 0.15, 0.085), 0.03, 82, 0.65, Vector3(3.0, 1.0, 0.3))
	_m.fabric = _flat(Color(0.16, 0.19, 0.26), 0.95)
	_m.blanket = _flat(Color(0.3, 0.05, 0.05), 0.95)
	_m.pillow = _flat(Color(0.7, 0.67, 0.6), 0.95)
	_m.plastic = _flat(Color(0.02, 0.02, 0.02), 0.35)
	_m.metal = _textured(Color(0.13, 0.14, 0.15), Color(0.3, 0.3, 0.31), 0.03, 83, 0.45, Vector3.ONE, {"metallic": 0.6})
	_m.bulb = _emissive(WARM, 6.0)
	_m.card = _flat(Color(0.9, 0.9, 0.88), 0.45)
	_m.pipe = _flat(Color(0.2, 0.2, 0.19), 0.6, {"metallic": 0.7})


func _backdrop() -> void:
	var room := _group(_root, "Backdrop")
	var arch := CSGCombiner3D.new()
	_add(room, arch, "Architecture")
	_csg(arch, "Shell", Vector3(0, 1.4, 0), Vector3(6, 3.2, 5.4), _m.plaster)
	_csg(arch, "Interior", Vector3(0, 1.4, 0), Vector3(5, 2.8, 4.5), _m.plaster, true)
	_csg(arch, "Floor", Vector3(0, 0, 0), Vector3(5.1, 0.04, 4.6), _m.wood)

	_box(room, "BedFrame", Vector3(1.05, 0.32, 2.05), Vector3(-1.9, 0.16, 1.1), _m.wood)
	_box(room, "Mattress", Vector3(0.95, 0.18, 1.95), Vector3(-1.9, 0.41, 1.1), _m.fabric, false)
	_box(room, "Pillow", Vector3(0.6, 0.12, 0.35), Vector3(-1.9, 0.56, 1.85), _m.pillow, false, Vector3(0, 6, 0))
	_box(room, "Blanket", Vector3(1.0, 0.07, 1.15), Vector3(-1.85, 0.53, 0.5), _m.blanket, false, Vector3(3, -9, 2))
	_box(room, "Desk", Vector3(0.7, 0.04, 1.4), Vector3(2.0, 0.75, 0.6), _m.wood)
	_box(room, "Monitor", Vector3(0.05, 0.34, 0.55), Vector3(2.2, 1.0, 0.65), _m.plastic, false)
	_box(room, "Door", Vector3(0.9, 2.05, 0.05), Vector3(1.2, 1.03, -2.2), _m.wood, false)
	for i in 5:
		_card(room, Vector3(_rng.randf_range(-1.0, 1.4), 0.03, _rng.randf_range(-1.6, 1.0)), i)

	# The single swinging bulb keeps the backdrop alive.
	_mesh(room, "Cord", _cylinder(0.006, 0.3), Vector3(0.0, 2.63, 0.2), _m.plastic)
	var bulb := _omni(room, "CeilingBulb", Vector3(0.0, 2.42, 0.2), WARM, 1.5, 6.0, true, Light.BROKEN)
	_mesh(bulb, "Glass", _sphere(0.05), Vector3(0.0, 0.03, 0.0), _m.bulb)
	bulb.set("emissive_mesh", NodePath("Glass"))
	# Red light through the window, like the hub.
	var outside := SpotLight3D.new()
	outside.light_color = Color(1.0, 0.16, 0.1)
	outside.light_energy = 7.0
	outside.spot_range = 9.0
	outside.spot_angle = 24.0
	outside.shadow_enabled = true
	outside.light_volumetric_fog_energy = 2.5
	_add(room, outside, "RedSkyLight").position = Vector3(-3.6, 2.6, -0.4)
	outside.rotation_degrees = Vector3(-25, -70, 0)

	var camera := Camera3D.new()
	camera.fov = 55.0
	_add(_root, camera, "BackgroundCamera")
	var eye := Vector3(1.9, 1.5, 2.0)
	camera.transform = Transform3D(Basis.looking_at(Vector3(-1.4, 0.9, -0.6) - eye), eye)
	_unique.append(camera)


# =========================================================================
# UI
# =========================================================================

func _ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	_add(_root, layer, "UI")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(layer, root, "Root")

	var title := _ui_label(&"MENU_TITLE", 62, TITLE_COLOR)
	_place(title, Vector4(0.06, 0.12, 0.7, 0.24))
	_add(root, title, "Title")
	var subtitle := _ui_label(&"MENU_SUBTITLE", 20, Color(0.7, 0.68, 0.65))
	_place(subtitle, Vector4(0.065, 0.24, 0.7, 0.3))
	_add(root, subtitle, "Subtitle")
	var rule := ColorRect.new()
	rule.color = ACCENT
	_place(rule, Vector4(0.06, 0.235, 0.34, 0.235))
	rule.offset_bottom = 2
	_add(root, rule, "Rule")

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_place(buttons, Vector4(0.06, 0.4, 0.34, 0.8))
	_add(root, buttons, "Buttons")
	_unique.append(buttons)
	for entry in [["StartButton", &"MENU_START"], ["LevelSelectButton", &"MENU_LEVEL_SELECT"],
			["SettingsButton", &"MENU_SETTINGS"], ["QuitButton", &"MENU_QUIT"]]:
		var button := _ui_button(entry[1])
		_add(buttons, button, entry[0])
		_unique.append(button)

	var version := _ui_label(&"", 13, Color(0.5, 0.5, 0.5))
	version.text = "v0.3 — prototype"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(version, Vector4(0.6, 0.94, 0.98, 0.99))
	_add(root, version, "Version")

	# Settings panel (fills itself in at runtime).
	var settings_center := CenterContainer.new()
	settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(layer, settings_center, "SettingsCenter")
	var settings := PanelContainer.new()
	settings.set_script(SETTINGS_PANEL)
	_add(settings_center, settings, "SettingsPanel")
	_unique.append(settings)

	# Level select.
	var level_center := CenterContainer.new()
	level_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(layer, level_center, "LevelCenter")
	var level_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.93)
	style.border_color = ACCENT
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(26)
	level_panel.add_theme_stylebox_override("panel", style)
	_add(level_center, level_panel, "LevelSelect")
	_unique.append(level_panel)
	var level_box := VBoxContainer.new()
	level_box.add_theme_constant_override("separation", 10)
	_add(level_panel, level_box, "Box")
	_add(level_box, _ui_label(&"MENU_LEVEL_SELECT", 26, ACCENT), "Header")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	_add(level_box, list, "LevelList")
	_unique.append(list)
	var back := _ui_button(&"MENU_BACK")
	back.custom_minimum_size = Vector2(340, 38)
	_add(level_box, back, "LevelSelectBack")
	_unique.append(back)


func _ui_label(key: StringName, size: int, color: Color) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = 5
	settings.outline_color = Color(0, 0, 0, 0.85)
	label.label_settings = settings
	label.text = String(key) # a translation key: Godot translates it automatically
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Blood-smear menu entry (ui/blood_button.gd styles itself at runtime).
func _ui_button(key: StringName) -> Button:
	var button := Button.new()
	button.set_script(BLOOD_BUTTON)
	button.text = String(key)
	button.custom_minimum_size = Vector2(300, 46)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 22)
	return button


## anchors = (left, top, right, bottom) in screen fractions.
func _place(control: Control, anchors: Vector4) -> void:
	control.anchor_left = anchors.x
	control.anchor_top = anchors.y
	control.anchor_right = anchors.z
	control.anchor_bottom = anchors.w
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0
