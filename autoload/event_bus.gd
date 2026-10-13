extends Node
## Global signal hub (Autoload: EventBus).
## Systems emit and listen here instead of holding references to each other,
## so levels, UI, AI and the player stay fully decoupled.

# --- Game flow ---
signal game_state_changed(new_state: int, old_state: int)
signal level_started(level_id: StringName)
signal level_completed(level_id: StringName)
signal level_failed(level_id: StringName, reason: String)
signal ally_fate_decided(escaped_together: bool) # Level 4 -> decides the ending
signal ending_reached(is_good: bool)

# --- Level timer / timeline ---
signal level_timer_tick(time_left: float)
signal timeline_event(event_id: StringName)

# --- Player ---
signal player_spawned(player: Node3D)
signal player_died(reason: String)
signal player_stamina_changed(current: float, maximum: float)
signal player_breath_changed(current: float, maximum: float)
signal player_heartbeat_changed(bpm: float, normalized: float)
signal player_heartbeat_critical(is_critical: bool)
signal player_hidden_changed(is_hidden: bool)
## Something is listening right outside the player's hiding spot: mash [Q].
signal player_hide_check_changed(is_checked: bool)
signal player_hold_meter_changed(value: float) # 0..1, 0 = the breath got out
signal interaction_prompt_changed(text: String) # "" = hide prompt

# --- Narrative / UI ---
signal subtitle_requested(text: String, duration: float)
signal objective_changed(text: String)
signal announcement(text: String, duration: float)
signal message_requested(title: String, body: String) # phone / notes panel
signal message_closed

# --- Items ---
signal item_picked(item_id: StringName)
signal inventory_changed(items: Dictionary, selected: StringName)

# --- AI perception ---
## `loudness` is a hearing radius in meters: any listener closer than this hears it.
signal noise_emitted(position: Vector3, loudness: float, source: Node)
