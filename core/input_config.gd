class_name InputConfig
extends RefCounted
## Registers default input actions at startup. Actions already defined in
## Project Settings > Input Map are left untouched, so you can rebind there.

const KEY_BINDINGS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"sprint": [KEY_SHIFT],
	&"crouch": [KEY_C, KEY_CTRL],
	&"jump": [KEY_SPACE],
	&"interact": [KEY_E],
	&"hold_breath": [KEY_Q],
	&"cycle_item": [KEY_R],
	&"flashlight": [KEY_F],
	&"pause": [KEY_ESCAPE],
}

const MOUSE_BINDINGS := {
	&"throw": [MOUSE_BUTTON_LEFT],
	&"aim": [MOUSE_BUTTON_RIGHT],
}


static func register_defaults() -> void:
	for action: StringName in KEY_BINDINGS:
		if _ensure_action(action):
			for keycode: Key in KEY_BINDINGS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = keycode
				InputMap.action_add_event(action, event)
	for action: StringName in MOUSE_BINDINGS:
		if _ensure_action(action):
			for button: MouseButton in MOUSE_BINDINGS[action]:
				var event := InputEventMouseButton.new()
				event.button_index = button
				InputMap.action_add_event(action, event)


## Returns true when the action was newly created and needs default events.
static func _ensure_action(action: StringName) -> bool:
	if InputMap.has_action(action):
		return false
	InputMap.add_action(action)
	return true
