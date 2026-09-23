class_name Announcer
extends Node
## Game-master style PA announcements: chime, on-screen banner, and the
## operating system's text-to-speech voice when available (Windows SAPI
## voices work out of the box; requires audio/general/text_to_speech).

@export var use_voice := true
@export var voice_volume := 70 ## 0-100
@export var voice_pitch := 0.8
@export var voice_rate := 0.85
@export var preferred_voices: PackedStringArray = ["Zira", "Female", "Hazel", "Susan"]

var _chime: AudioStreamPlayer
var _voice_id := ""


func _ready() -> void:
	SettingsManager.language_changed.connect(func(_locale: String) -> void: _voice_id = _pick_voice())
	_chime = AudioStreamPlayer.new()
	_chime.bus = "SFX"
	_chime.stream = ProceduralAudio.get_stream(&"chime")
	_chime.volume_db = -4.0
	add_child(_chime)
	if use_voice and ProjectSettings.get_setting("audio/general/text_to_speech", false):
		_voice_id = _pick_voice()


## `text` is a translation key (or plain text). Await it to wait for the end.
func announce(text: String, with_chime: bool = true) -> void:
	text = Localization.t(text)
	if with_chime:
		_chime.play()
		await get_tree().create_timer(1.1).timeout
	var duration := maxf(3.0, text.length() * 0.075)
	EventBus.announcement.emit(text, duration)
	if _voice_id != "":
		DisplayServer.tts_speak(text, _voice_id, voice_volume, voice_pitch, voice_rate)
	await get_tree().create_timer(duration).timeout


## A voice for the current language, or "" (then it is banner + subtitle only).
func _pick_voice() -> String:
	var locale := TranslationServer.get_locale().substr(0, 2)
	var matching: Array[Dictionary] = []
	for voice in DisplayServer.tts_get_voices():
		if String(voice.get("language", "")).begins_with(locale):
			matching.append(voice)
	for wanted in preferred_voices:
		for voice in matching:
			if wanted.to_lower() in String(voice.get("name", "")).to_lower():
				return voice["id"]
	return matching[0]["id"] if not matching.is_empty() else ""
