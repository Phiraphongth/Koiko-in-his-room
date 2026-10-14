class_name BloodButton
extends Button
## Menu entry with a small diamond bullet and no frame. On hover / focus a
## blood smear brushes in behind the text and drips run down from it, letting
## a drop fall now and then. Used by every menu (main, level select, pause,
## settings) so they all match.

const TEXT := Color(0.8, 0.79, 0.76)
const BLOOD := Color(0.5, 0.02, 0.02)
const BLOOD_DARK := Color(0.3, 0.01, 0.01)
const BULLET_X := 14.0
const TEXT_LEFT := 34
const TAIL := 70.0 # how far the smear runs past the text
const SWEEP_TIME := 0.16
const FADE_TIME := 0.22
const DRIP_MAX := 20.0 # px below the smear
const DROP_PERIOD := 1.7 # seconds between falling drops per drip

var _ink: Control # drawn behind the button text (show_behind_parent)
var _active := false
var _hover_time := 0.0
var _sweep := 0.0
var _alpha := 0.0
var _edge_top: PackedFloat32Array = []
var _edge_bottom: PackedFloat32Array = []
var _tails: PackedFloat32Array = [] # reach of each frayed streak, 0-1 of the tail
var _drips: Array[Dictionary] = [] # {x (0-1 of smear), width, length (0-1), delay, speed, phase}


func _ready() -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = TEXT_LEFT
	empty.content_margin_right = 24
	empty.content_margin_top = 6
	empty.content_margin_bottom = 6
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, empty)
	add_theme_color_override("font_color", TEXT)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.WHITE)
	add_theme_color_override("font_disabled_color", Color(0.38, 0.38, 0.38))

	_ink = Control.new()
	_ink.show_behind_parent = true
	_ink.mouse_filter = MOUSE_FILTER_IGNORE
	_ink.set_anchors_preset(PRESET_FULL_RECT)
	_ink.draw.connect(_draw_ink)
	add_child(_ink, false, INTERNAL_MODE_FRONT)

	_shape()
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	set_process(false)


func _refresh() -> void:
	var active := (is_hovered() or has_focus()) and not disabled
	if active == _active:
		return
	_active = active
	if active and _alpha <= 0.0:
		_shape() # every hover leaves a slightly different smear
	set_process(true)


func _process(delta: float) -> void:
	if _active:
		_hover_time += delta
		_sweep = minf(_sweep + delta / SWEEP_TIME, 1.0)
		_alpha = 1.0
	else:
		_alpha -= delta / FADE_TIME
		if _alpha <= 0.0:
			_alpha = 0.0
			_sweep = 0.0
			_hover_time = 0.0
			set_process(false)
	_ink.queue_redraw()
	queue_redraw()


## Random ragged edges and drip layout for the next smear.
func _shape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_edge_top.clear()
	_edge_bottom.clear()
	for i in 13:
		_edge_top.append(rng.randf_range(-2.5, 2.5))
		_edge_bottom.append(rng.randf_range(-2.5, 2.5))
	_tails.clear()
	for i in 7:
		_tails.append(rng.randf_range(0.25, 1.0))
	_drips.clear()
	for i in rng.randi_range(3, 5):
		_drips.append({
			"x": rng.randf_range(0.08, 0.8),
			"width": rng.randf_range(1.8, 3.6),
			"length": rng.randf_range(0.35, 1.0),
			"delay": rng.randf_range(0.05, 0.6),
			"speed": rng.randf_range(0.9, 2.2), # fraction of full length per second
			"phase": rng.randf_range(0.0, DROP_PERIOD),
		})


func _draw() -> void:
	# Diamond bullet; turns white while the smear is up.
	var c := Vector2(BULLET_X, size.y * 0.5)
	var r := 4.0
	var color := TEXT.lerp(Color.WHITE, _alpha) if not disabled else Color(0.38, 0.38, 0.38)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)


func _draw_ink() -> void:
	if _alpha <= 0.0:
		return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var text_width := font.get_string_size(atr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var full := minf(TEXT_LEFT + text_width + TAIL, size.x + TAIL * 0.5)
	var length := full * ease(_sweep, 0.35)
	var top := 3.0
	var bottom := size.y - 3.0
	var blood := Color(BLOOD, _alpha * 0.92)
	var dark := Color(BLOOD_DARK, _alpha)

	# The smear: ragged top and bottom, frayed into streaks at the tail.
	var segments := _edge_top.size() - 1
	var body := PackedVector2Array()
	for i in segments + 1:
		var f := float(i) / segments
		body.append(Vector2(length * f * 0.82, top + _edge_top[i]))
	for i in range(segments, -1, -1):
		var f := float(i) / segments
		body.append(Vector2(length * f * 0.82, bottom + _edge_bottom[i]))
	_ink.draw_colored_polygon(body, blood)
	# Bristle streaks tapering to points past the end of the body.
	var tail_from := length * 0.82 - 4.0
	var half := (bottom - top) / _tails.size() * 0.75
	for i in _tails.size():
		var y := lerpf(top + half, bottom - half, float(i) / (_tails.size() - 1))
		var reach := tail_from + (length - tail_from) * _tails[i]
		_ink.draw_colored_polygon(PackedVector2Array([
			Vector2(tail_from, y - half), Vector2(reach, y + (_tails[i] - 0.5) * 2.0), Vector2(tail_from, y + half),
		]), blood)
	# A darker brush streak through the middle for texture.
	_ink.draw_line(Vector2(6, size.y * 0.62), Vector2(length * 0.7, size.y * 0.58), Color(BLOOD_DARK, _alpha * 0.5), 2.0)

	# Drips running down from the bottom edge.
	for drip in _drips:
		var x: float = drip.x * full
		if x > length:
			continue
		var grown := clampf((_hover_time - drip.delay) * drip.speed, 0.0, 1.0)
		var run: float = ease(grown, 0.45) * drip.length * DRIP_MAX
		var width: float = drip.width
		if run < 1.0:
			continue
		var tip := Vector2(x, bottom + run)
		_ink.draw_colored_polygon(PackedVector2Array([
			Vector2(x - width, bottom - 1.0), Vector2(x + width, bottom - 1.0),
			tip + Vector2(width * 0.45, 0), tip + Vector2(-width * 0.45, 0),
		]), dark)
		_ink.draw_circle(tip, width * 0.8, dark)
		# Once full, a drop breaks off and falls every DROP_PERIOD seconds.
		if grown >= 1.0:
			var t := fmod(_hover_time + drip.phase, DROP_PERIOD)
			if t < 0.55:
				var fall := tip + Vector2(0, 4.0 + 260.0 * t * t)
				_ink.draw_circle(fall, width * 0.6, Color(BLOOD_DARK, _alpha * (1.0 - t / 0.55)))
