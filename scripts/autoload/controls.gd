extends Node
## Registers every input action in code so all bindings live in one readable
## table instead of serialized InputEvent blobs inside project.godot.

const DEADZONE := 0.35

const KEYS := {
	"move_left": [KEY_LEFT, KEY_A],
	"move_right": [KEY_RIGHT, KEY_D],
	"move_up": [KEY_UP, KEY_W],
	"move_down": [KEY_DOWN, KEY_S],
	"jump": [KEY_SPACE, KEY_Z, KEY_C, KEY_J],
	"dash": [KEY_X, KEY_SHIFT, KEY_K],
	"pause": [KEY_ESCAPE, KEY_P],
	"restart": [KEY_R],
	"mute": [KEY_M],
}

const PAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP],
	"move_down": [JOY_BUTTON_DPAD_DOWN],
	"jump": [JOY_BUTTON_A],
	"dash": [JOY_BUTTON_X, JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
	"pause": [JOY_BUTTON_START],
	"restart": [JOY_BUTTON_BACK],
}

## action -> [axis, direction]
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}


func _enter_tree() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		for keycode: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

	for action: String in PAD_BUTTONS:
		for button: JoyButton in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)

	for action: String in PAD_AXES:
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)
