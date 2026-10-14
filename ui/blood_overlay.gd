class_name BloodOverlay
extends CanvasLayer
## Blood on the lens for death cutscenes. Each splat() throws a cluster of
## dark red blobs at the screen; some of them run down it as drips. Sits under
## HorrorFX (layer 5), so the vignette, tint and blur are applied on top.
##
##   var blood := BloodOverlay.new()
##   add_child(blood)
##   blood.splat(1.0)

const COLOR := Color(0.32, 0.0, 0.01, 0.92)
const DARK := Color(0.12, 0.0, 0.0, 0.95)

var _canvas: Control
var _blobs: Array[Dictionary] = [] # {pos, radius, color}
var _drips: Array[Dictionary] = [] # {pos, width, length, target, speed}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 4
	_rng.randomize()
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_blood)
	add_child(_canvas)


func _process(delta: float) -> void:
	if _drips.is_empty():
		return
	for drip in _drips:
		if drip.length < drip.target:
			drip.speed = maxf(drip.speed * (1.0 - delta * 0.8), 14.0)
			drip.length = minf(drip.length + drip.speed * delta, drip.target)
	_canvas.queue_redraw()


## Throws blood at the lens. `strength` 0..1 scales size and amount;
## `center` (0..1 screen UV) aims the splat, defaults to somewhere random.
func splat(strength: float = 1.0, center := Vector2(-1.0, -1.0)) -> void:
	var size := _canvas.size
	if size == Vector2.ZERO:
		size = get_viewport().get_visible_rect().size
	var unit := minf(size.x, size.y)
	var origin := center * size if center.x >= 0.0 else \
		Vector2(_rng.randf_range(0.15, 0.85), _rng.randf_range(0.1, 0.7)) * size
	# One heavy blob, then spatter thrown outwards from it.
	var main_radius := unit * _rng.randf_range(0.06, 0.11) * (0.5 + strength)
	_add_blob(origin, main_radius, DARK)
	for i in int(5 + 10 * strength):
		var offset := Vector2.from_angle(_rng.randf() * TAU) * main_radius * _rng.randf_range(0.6, 1.4)
		_add_blob(origin + offset, main_radius * _rng.randf_range(0.25, 0.55), COLOR)
	for i in int(10 + 25 * strength):
		var throw := Vector2.from_angle(_rng.randf() * TAU) * unit * _rng.randf_range(0.08, 0.45) * strength
		_add_blob(origin + throw, unit * _rng.randf_range(0.004, 0.018), COLOR)
	for i in int(2 + 4 * strength):
		var start := origin + Vector2(_rng.randf_range(-1.0, 1.0) * main_radius, main_radius * 0.4)
		_drips.append({
			"pos": start,
			"width": unit * _rng.randf_range(0.006, 0.016),
			"length": 0.0,
			"target": unit * _rng.randf_range(0.12, 0.6),
			"speed": unit * _rng.randf_range(0.25, 0.6),
		})
	_canvas.queue_redraw()


func clear() -> void:
	_blobs.clear()
	_drips.clear()
	_canvas.queue_redraw()


func _add_blob(pos: Vector2, radius: float, color: Color) -> void:
	_blobs.append({"pos": pos, "radius": radius, "color": color})


func _draw_blood() -> void:
	for blob in _blobs:
		_canvas.draw_circle(blob.pos, blob.radius, blob.color)
	for drip in _drips:
		if drip.length <= 0.0:
			continue
		var end: Vector2 = drip.pos + Vector2(0.0, drip.length)
		_canvas.draw_line(drip.pos, end, COLOR, drip.width)
		_canvas.draw_circle(end, drip.width * 0.9, COLOR) # the bead at the tip
