extends Control

# First real application screen for ios-godot-lab.
# Everything shown here is intentionally a probe: a capability is only considered
# validated after the exact build has run successfully on a real iPhone.

const ACCENT := Color("78a9ff")
const TEXT_MAIN := Color("f3f6fb")
const TEXT_MUTED := Color("9ca8b8")
const CARD_BG := Color("151c27")
const CARD_BORDER := Color("263247")
const GOOD := Color("75d49b")
const WARN := Color("f3c96b")

var _touch_count := 0
var _touch_value: Label
var _touch_position: Label
var _accelerometer_value: Label
var _gravity_value: Label
var _gyroscope_value: Label
var _magnetometer_value: Label
var _platform_value: Label
var _screen_value: Label
var _network_value: Label
var _build_value: Label
var _haptic_value: Label


func _ready() -> void:
	_build_interface()
	_refresh_static_device_info()
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(_accelerometer_value):
		return

	_accelerometer_value.text = _format_vector(Input.get_accelerometer(), "m/s²")
	_gravity_value.text = _format_vector(Input.get_gravity(), "m/s²")
	_gyroscope_value.text = _format_vector(Input.get_gyroscope(), "rad/s")
	_magnetometer_value.text = _format_vector(Input.get_magnetometer(), "µT")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_register_touch(event.position, event.index)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_register_touch(event.position, -1)


func _register_touch(position: Vector2, finger_index: int) -> void:
	_touch_count += 1
	if is_instance_valid(_touch_value):
		_touch_value.text = "%d touch%s detected" % [_touch_count, "" if _touch_count == 1 else "es"]
	if is_instance_valid(_touch_position):
		var source := "mouse" if finger_index < 0 else "finger %d" % finger_index
		_touch_position.text = "%s · x %.1f · y %.1f" % [source, position.x, position.y]


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("090e16")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 68)
	margin.add_theme_constant_override("margin_bottom", 72)
	scroll.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 22)
	margin.add_child(column)

	var eyebrow := _make_label("IOS · GODOT · DEVICE LAB", 18, ACCENT)
	eyebrow.add_theme_constant_override("outline_size", 0)
	column.add_child(eyebrow)

	var title := _make_label("iPhone Lab", 48, TEXT_MAIN)
	column.add_child(title)

	var intro := _make_label(
		"A real-device test bench for touch, motion sensors, networking and future native iOS bridges.",
		22,
		TEXT_MUTED
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)

	var build_card := _make_card("BUILD IDENTITY", "Every future IPA will stamp its exact Git SHA here.")
	_build_value = _add_value_row(build_card, "Build", "local · unstamped")
	_platform_value = _add_value_row(build_card, "Platform", "detecting…")
	_screen_value = _add_value_row(build_card, "Viewport", "detecting…")
	column.add_child(build_card.get_parent())

	var touch_card := _make_card("TOUCH", "Tap anywhere or use the button. Multi-touch events will be counted on iPhone.")
	_touch_value = _add_value_row(touch_card, "Events", "0 touches detected")
	_touch_position = _add_value_row(touch_card, "Last input", "none")
	var touch_button := _make_button("TEST TOUCH")
	touch_button.pressed.connect(func() -> void:
		_register_touch(get_viewport().get_visible_rect().size * 0.5, -1)
	)
	touch_card.add_child(touch_button)
	column.add_child(touch_card.get_parent())

	var motion_card := _make_card(
		"MOTION · LIVE",
		"Godot reads these sensors directly on iOS. Zero values are expected when running on a normal Windows PC."
	)
	_accelerometer_value = _add_value_row(motion_card, "Accelerometer", "waiting…")
	_gravity_value = _add_value_row(motion_card, "Gravity", "waiting…")
	_gyroscope_value = _add_value_row(motion_card, "Gyroscope", "waiting…")
	_magnetometer_value = _add_value_row(motion_card, "Magnetometer", "waiting…")
	column.add_child(motion_card.get_parent())

	var network_card := _make_card(
		"NETWORK",
		"This is the base for a future local connection to desktop software over HTTP, UDP, TCP or WebSocket."
	)
	_network_value = _add_value_row(network_card, "Local addresses", "detecting…")
	column.add_child(network_card.get_parent())

	var haptic_card := _make_card("HAPTIC TEST", "The button calls Godot's handheld vibration API. Real behavior must be validated on iPhone.")
	_haptic_value = _add_value_row(haptic_card, "Status", "not tested")
	var haptic_button := _make_button("TEST VIBRATION")
	haptic_button.pressed.connect(_on_haptic_pressed)
	haptic_card.add_child(haptic_button)
	column.add_child(haptic_card.get_parent())

	var capability_card := _make_card(
		"CAPABILITY ROADMAP",
		"Direct means Godot already exposes the API. Bridge means we will expose an Apple framework through one native IOSBridge plugin."
	)
	_add_capability(capability_card, "Touch / multi-touch", "DIRECT", GOOD)
	_add_capability(capability_card, "Accelerometer / gyro / gravity", "DIRECT", GOOD)
	_add_capability(capability_card, "Camera / microphone", "DIRECT + PERMISSION", GOOD)
	_add_capability(capability_card, "HTTP / TCP / UDP / WebSocket", "DIRECT", GOOD)
	_add_capability(capability_card, "Bluetooth LE", "IOSBRIDGE · COREBLUETOOTH", WARN)
	_add_capability(capability_card, "GPS / Core Location", "IOSBRIDGE", WARN)
	_add_capability(capability_card, "NFC", "IOSBRIDGE · CORENFC", WARN)
	_add_capability(capability_card, "ARKit / LiDAR", "IOSBRIDGE / PLUGIN", WARN)
	column.add_child(capability_card.get_parent())

	var footer := _make_label(
		"STATUS · IMPLEMENTED, NOT YET VALIDATED ON IPHONE\nNo capability becomes ‘validated’ until the exact SHA is built and tested on the real device.",
		17,
		TEXT_MUTED
	)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(footer)


func _make_card(title_text: String, description: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = CARD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(22)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 26
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	var title := _make_label(title_text, 21, TEXT_MAIN)
	content.add_child(title)

	if not description.is_empty():
		var help := _make_label(description, 17, TEXT_MUTED)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(help)

	return content


func _add_value_row(parent: VBoxContainer, key: String, value: String) -> Label:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var key_label := _make_label(key, 18, TEXT_MUTED)
	key_label.custom_minimum_size.x = 190
	row.add_child(key_label)

	var value_label := _make_label(value, 18, TEXT_MAIN)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value_label)
	return value_label


func _add_capability(parent: VBoxContainer, name: String, path: String, status_color: Color) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var name_label := _make_label(name, 17, TEXT_MAIN)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)

	var status := _make_label(path, 14, status_color)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size.x = 220
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(status)


func _make_label(text_value: String, font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	return label


func _make_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 62
	button.add_theme_font_size_override("font_size", 18)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("1f2b3d")
	normal.border_color = Color("33445e")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(16)
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color("293850")
	button.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color("36527a")
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _refresh_static_device_info() -> void:
	var platform := OS.get_name()
	var model := OS.get_model_name()
	_platform_value.text = platform if model.is_empty() else "%s · %s" % [platform, model]

	var viewport_size := get_viewport().get_visible_rect().size
	_screen_value.text = "%d × %d" % [int(viewport_size.x), int(viewport_size.y)]

	var addresses := IP.get_local_addresses()
	var useful: Array[String] = []
	for address in addresses:
		var value := str(address)
		if value == "127.0.0.1" or value == "::1":
			continue
		useful.append(value)
	_network_value.text = "none exposed" if useful.is_empty() else ", ".join(useful.slice(0, 4))

	var build := _read_build_info()
	_build_value.text = "%s · %s · %s" % [
		str(build.get("version", "0.1.0-dev")),
		str(build.get("git_sha", "LOCAL")),
		str(build.get("channel", "local"))
	]


func _read_build_info() -> Dictionary:
	const PATH := "res://config/build_info.json"
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _on_haptic_pressed() -> void:
	Input.vibrate_handheld(80)
	_haptic_value.text = "request sent · validate on iPhone"


func _format_vector(value: Vector3, unit: String) -> String:
	return "x %7.3f · y %7.3f · z %7.3f %s" % [value.x, value.y, value.z, unit]
