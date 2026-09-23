extends CanvasLayer
## Full-screen fade overlay (Autoload: SceneTransition).
## Usage: `await SceneTransition.fade_out()` ... `await SceneTransition.fade_in()`

const DEFAULT_DURATION := 0.5

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func fade_out(duration: float = DEFAULT_DURATION) -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP # block clicks while covered
	await _fade_to(1.0, duration)


func fade_in(duration: float = DEFAULT_DURATION) -> void:
	await _fade_to(0.0, duration)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_color(color: Color) -> void:
	_rect.color = Color(color, _rect.color.a)


func _fade_to(alpha: float, duration: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_rect, "color:a", alpha, duration)
	await _tween.finished
