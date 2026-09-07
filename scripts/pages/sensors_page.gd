extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

var _accelerometer: Label
var _gravity: Label
var _gyroscope: Label
var _magnetometer: Label
var _touches: Label
var _drags: Label
var _last_input: Label
var _haptic_status: Label

var _touch_count := 0
var _drag_count := 0
var _drag_distance := 0.0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Sensors",
		"Live Godot sensor APIs plus a touch/drag probe designed to verify real iPhone gestures."
	)

	var motion := UI.make_card(self, "MOTION · LIVE")
	_accelerometer = UI.value_row(motion, "Accelerometer", "waiting…")
	_gravity = UI.value_row(motion, "Gravity", "waiting…")
	_gyroscope = UI.value_row(motion, "Gyroscope", "waiting…")
	_magnetometer = UI.value_row(motion, "Magnetometer", "waiting…")

	var touch := UI.make_card(
		self,
		"TOUCH & DRAG",
		"Tap or drag anywhere on this page. Vertical drag should also move the page even if the gesture begins over a card."
	)
	_touches = UI.value_row(touch, "Touch downs", "0")
	_drags = UI.value_row(touch, "Drag events", "0")
	_last_input = UI.value_row(touch, "Last input", "none")
	var reset := UI.button("RESET COUNTERS")
	reset.pressed.connect(_reset_counters)
	touch.add_child(reset)

	var haptic := UI.make_card(self, "HAPTICS")
	_haptic_status = UI.value_row(haptic, "Status", "not tested")
	var pulse := UI.button("TEST VIBRATION", true)
	pulse.pressed.connect(_test_haptic)
	haptic.add_child(pulse)

	set_process(true)
	set_process_input(true)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_accelerometer.text = _format_vector(Input.get_accelerometer(), "m/s²")
	_gravity.text = _format_vector(Input.get_gravity(), "m/s²")
	_gyroscope.text = _format_vector(Input.get_gyroscope(), "rad/s")
	_magnetometer.text = _format_vector(Input.get_magnetometer(), "µT")


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if event is InputEventScreenTouch and event.pressed:
		_touch_count += 1
		_touches.text = str(_touch_count)
		_last_input.text = "finger %d · x %.1f · y %.1f" % [
			event.index,
			event.position.x,
			event.position.y
		]
	elif event is InputEventScreenDrag:
		_drag_count += 1
		_drag_distance += event.relative.length()
		_drags.text = "%d · %.0f px" % [_drag_count, _drag_distance]
		_last_input.text = "drag %d · Δ %.1f, %.1f" % [
			event.index,
			event.relative.x,
			event.relative.y
		]


func _reset_counters() -> void:
	_touch_count = 0
	_drag_count = 0
	_drag_distance = 0.0
	_touches.text = "0"
	_drags.text = "0"
	_last_input.text = "none"


func _test_haptic() -> void:
	Input.vibrate_handheld(90)
	_haptic_status.text = "request sent"


func _format_vector(value: Vector3, unit: String) -> String:
	return "x %.3f · y %.3f · z %.3f %s" % [value.x, value.y, value.z, unit]
