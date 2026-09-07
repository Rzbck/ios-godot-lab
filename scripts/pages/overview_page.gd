extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

var _platform_value: Label
var _viewport_value: Label
var _addresses_value: Label
var _build_value: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Overview",
		"Real-device capability lab. Each page isolates one group of iPhone APIs, live telemetry and network tools."
	)

	var identity := UI.make_card(self, "BUILD & DEVICE", "The exact Git SHA is stamped by the iOS workflow before export.")
	_build_value = UI.value_row(identity, "Build", "reading…")
	_platform_value = UI.value_row(identity, "Platform", "reading…")
	_viewport_value = UI.value_row(identity, "Viewport", "reading…")
	_addresses_value = UI.value_row(identity, "Network", "reading…")

	var available := UI.make_card(
		self,
		"CAPABILITY MATRIX",
		"V2 exposes direct Godot APIs, a native iOS bridge and an opt-in PowerShell telemetry path."
	)
	_add_status(available, "Live PowerShell telemetry + ACK / RTT", "WS / HTTP", UI.ACCENT)
	_add_status(available, "Touch / drag / scroll", "DIRECT", UI.GOOD)
	_add_status(available, "Accelerometer / gravity / gyro / magnetometer", "DIRECT", UI.GOOD)
	_add_status(available, "Haptics", "DIRECT", UI.GOOD)
	_add_status(available, "GPS / CoreLocation", "IOSLAB BRIDGE", UI.GOOD)
	_add_status(available, "Bluetooth LE scan", "IOSLAB BRIDGE", UI.GOOD)
	_add_status(available, "ARKit / LiDAR availability probe", "IOSLAB BRIDGE", UI.GOOD)
	_add_status(available, "NFC availability probe", "IOSLAB BRIDGE", UI.WARN)
	_add_status(available, "Camera preview", "GODOT CAMERA", UI.GOOD)
	_add_status(available, "Microphone level capture", "GODOT AUDIO", UI.GOOD)
	_add_status(available, "HTTP / HTTPS", "DIRECT", UI.GOOD)
	_add_status(available, "WebSocket / WSS", "DIRECT", UI.GOOD)
	_add_status(available, "UDP / OSC", "DIRECT", UI.GOOD)

	var scroll_test := UI.make_card(
		self,
		"SCROLL SURFACE TEST",
		"Drag vertically directly on this card. Content surfaces intentionally ignore pointer input so the parent ScrollContainer receives the gesture."
	)
	for index in range(1, 7):
		UI.value_row(scroll_test, "Row %02d" % index, "drag over me")

	var privacy := UI.make_card(
		self,
		"TELEMETRY POLICY",
		"Telemetry is explicit opt-in. Nothing is sent until you enter a receiver address and press START STREAM on the Telemetry page."
	)
	privacy.add_child(UI.label(
		"The diagnostic payload excludes Apple ID, UDID/private identifiers, signing/pairing material, clipboard contents, camera frames and microphone audio.",
		13,
		UI.MUTED
	))

	_refresh()


func _refresh() -> void:
	var build := _read_build_info()
	_build_value.text = "%s · %s · %s" % [
		str(build.get("version", "0.2.0-dev")),
		str(build.get("git_sha", "LOCAL")),
		str(build.get("channel", "local"))
	]

	var platform := OS.get_name()
	var model := OS.get_model_name()
	_platform_value.text = platform if model.is_empty() else "%s · %s" % [platform, model]

	var viewport := get_viewport().get_visible_rect().size
	_viewport_value.text = "%d × %d" % [int(viewport.x), int(viewport.y)]

	var addresses := IP.get_local_addresses()
	var useful: Array[String] = []
	for address in addresses:
		var value := str(address)
		if value == "127.0.0.1" or value == "::1":
			continue
		useful.append(value)
	_addresses_value.text = "none" if useful.is_empty() else ", ".join(useful.slice(0, 4))


func _add_status(parent: Container, name: String, state: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var left := UI.label(name, 12, UI.TEXT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var right := UI.label(state, 11, color)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)


func _read_build_info() -> Dictionary:
	const PATH := "res://config/build_info.json"
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
