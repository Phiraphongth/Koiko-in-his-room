class_name HorrorFX
extends CanvasLayer
## Screen-space horror effects + heartbeat audio. Vignette, grain and
## aberration intensify with the player's heart rate, and every beat above
## ~95 BPM pulses the screen and plays a thump. Also used by cutscenes for
## blinking / blurred wake-up vision.

const SHADER := preload("res://shaders/horror_overlay.gdshader")

@export var base_vignette := 0.35
@export var base_grain := 0.05
@export var base_aberration := 0.0015
@export var desaturation := 0.25
@export var heartbeat_audio := true
@export var heartbeat_threshold := 0.2 ## normalized heart rate where beats become audible

var _material: ShaderMaterial
var _heart_player: AudioStreamPlayer
var _bpm := 70.0
var _heart := 0.0
var _pulse := 0.0
var _beat_timer := 0.0
var _blink := 0.0
var _blur := 0.0


func _ready() -> void:
	layer = 5
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var rect := ColorRect.new()
	rect.material = _material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	_material.set_shader_parameter(&"grain", base_grain)
	_material.set_shader_parameter(&"desaturation", desaturation)

	_heart_player = AudioStreamPlayer.new()
	_heart_player.bus = "SFX"
	_heart_player.stream = ProceduralAudio.get_stream(&"heartbeat")
	add_child(_heart_player)
	EventBus.player_heartbeat_changed.connect(_on_heartbeat)


func _process(delta: float) -> void:
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		_beat_timer = 60.0 / maxf(_bpm, 40.0)
		_on_beat()
	_pulse = move_toward(_pulse, 0.0, delta * 2.5)
	_material.set_shader_parameter(&"pulse", _pulse)
	_material.set_shader_parameter(&"vignette", base_vignette + _heart * 0.35)
	_material.set_shader_parameter(&"aberration", base_aberration + _heart * 0.004)


func set_blink(value: float) -> void:
	_blink = value
	_material.set_shader_parameter(&"blink", value)


func set_blur(value: float) -> void:
	_blur = value
	_material.set_shader_parameter(&"blur", value)


func blink_to(value: float, duration: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_blink, _blink, value, duration)
	await tween.finished


func blur_to(value: float, duration: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_blur, _blur, value, duration)
	await tween.finished


func _on_heartbeat(bpm: float, normalized: float) -> void:
	_bpm = bpm
	_heart = normalized


func _on_beat() -> void:
	if _heart < heartbeat_threshold:
		return
	_pulse = _heart
	if heartbeat_audio:
		_heart_player.volume_db = linear_to_db(clampf(_heart * 1.2, 0.05, 1.0))
		_heart_player.play()
