extends CanvasLayer
## Temporary text readout of player/level stats. The real HUD comes later;
## this only listens to EventBus, so it can be dropped into any level.

var _label: Label
var _stats: Dictionary[String, String] = {}


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_label)

	EventBus.player_stamina_changed.connect(func(c: float, m: float) -> void: _set_stat("Stamina", "%d / %d" % [c, m]))
	EventBus.player_breath_changed.connect(func(c: float, m: float) -> void: _set_stat("Breath", "%.1f / %.1f s" % [c, m]))
	EventBus.player_heartbeat_changed.connect(func(bpm: float, _n: float) -> void: _set_stat("Heartbeat", "%d BPM" % bpm))
	EventBus.player_heartbeat_critical.connect(func(on: bool) -> void: _set_stat("Heart alarm", "!!! CRITICAL !!!" if on else "-"))
	EventBus.player_hidden_changed.connect(func(on: bool) -> void: _set_stat("Hidden", str(on)))
	EventBus.noise_emitted.connect(func(_p: Vector3, loud: float, _s: Node) -> void: _set_stat("Last noise", "%.1f m" % loud))
	EventBus.interaction_prompt_changed.connect(func(t: String) -> void: _set_stat("Prompt", "[E] " + t if t else "-"))
	EventBus.level_timer_tick.connect(func(t: float) -> void: _set_stat("Timer", "%02d:%02d" % [int(t) / 60, int(t) % 60]))
	EventBus.timeline_event.connect(func(id: StringName) -> void: _set_stat("Event", String(id)))
	EventBus.player_spawned.connect(_on_player_spawned)


func _on_player_spawned(player: Node3D) -> void:
	var p := player as Player
	if p:
		p.state_changed.connect(func(s: Player.State, _o: Player.State) -> void: _set_stat("State", Player.State.keys()[s]))


func _set_stat(key: String, value: String) -> void:
	_stats[key] = value
	var lines := PackedStringArray()
	for k: String in _stats:
		lines.append("%s: %s" % [k, _stats[k]])
	_label.text = "\n".join(lines)
