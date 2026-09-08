extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

var _motion_values: Dictionary = {}
var _touches: Label
var _drags: Label
var _last_input: Label
var _haptic_status: Label

var _touch_count := 0
var _drag_count := 0
var _drag_distance := 0.0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Motion",
		"Live sensor values use fixed X/Y/Z cells so changing numbers never reflow the page."
	)

	var motion := UI.make_card(self, "MOTION · LIVE")
	_motion_values["accelerometer"] = _add_vector_probe(motion, "Accelerometer", "m/s²")
	_motion_values["gravity"] = _add_vector_probe(motion, "Gravity", "m/s²")
	_motion_values["gyroscope"] = _add_vector_probe(motion, "Gyroscope", "rad/s")
	_motion_values["magnetometer"] = _add_vector_probe(motion, "Magnetometer", "µT")

	var touch := UI.make_card(
		self,
		"TOUCH & DRAG",
		"Tap or drag anywhere on this page. The page itself remains vertically scrollable."
	)
	_touches = UI.value_row(touch, "Touch downs", "0")
	_drags = UI.value_row(touch, "Drag events", "0")
	_last_input = UI.value_row(touch, "Last input", "none")
	var reset := UI.button("Reset Counters")
	reset.pressed.connect(_reset_counters)
	touch.add_child(reset)

	var haptic := UI.make_card(self, "HAPTICS")
	_haptic_status = UI.value_row(haptic, "Status", "not tested")
	var pulse := UI.button("Test Vibration", true)
	pulse.pressed.connect(_test_haptic)
	haptic.add_child(pulse)

	set_process(true)
	set_process_input(true)


func _add_vector_probe(parent: Container, title_text: String, unit: String) -> Array:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 6)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)

	var heading := HBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(heading)

	var title := UI.single_line_label(title_text, 13, UI.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(UI.single_line_label(unit, 11, UI.MUTED))

	var grid := HBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(grid)

	var values: Array = []
	for axis in ["X", "Y", "Z"]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 1)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)

		var axis_label := UI.single_line_label(axis, 10, UI.MUTED)
		axis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(axis_label)

		var value := UI.single_line_label("+0.000", 15, UI.ACCENT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.custom_minimum_size.y = 24
		cell.add_child(value)
		values.append(value)

	var separator := HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(separator)
	return values


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_set_vector(_motion_values["accelerometer"], Input.get_accelerometer())
	_set_vector(_motion_values["gravity"], Input.get_gravity())
	_set_vector(_motion_values["gyroscope"], Input.get_gyroscope())
	_set_vector(_motion_values["magnetometer"], Input.get_magnetometer())


func _set_vector(labels: Array, value: Vector3) -> void:
	if labels.size() < 3:
		return
	(labels[0] as Label).text = "%+.3f" % value.x
	(labels[1] as Label).text = "%+.3f" % value.y
	(labels[2] as Label).text = "%+.3f" % value.z


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if event is InputEventScreenTouch and event.pressed:
		_touch_count += 1
		_touches.text = str(_touch_count)
		_last_input.text = "finger %d · x %.0f · y %.0f" % [
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
