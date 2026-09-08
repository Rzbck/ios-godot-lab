extends VBoxContainer

signal navigate_requested(page_name: String)

const UI = preload("res://scripts/ui.gd")

var _platform_value: Label
var _viewport_value: Label
var _build_value: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Home",
		"Real-device iPhone lab for motion, location, camera, networking and live diagnostics."
	)

	_build_device_card()
	_build_quick_actions()
	_build_feature_summary()

	_refresh()


func _build_device_card() -> void:
	var card := UI.make_card(self, "THIS DEVICE")
	_build_value = UI.value_row(card, "Build", "reading…")
	_platform_value = UI.value_row(card, "Device", "reading…")
	_viewport_value = UI.value_row(card, "Canvas", "reading…")


func _build_quick_actions() -> void:
	var card := UI.make_card(
		self,
		"QUICK START",
		"Open the tool you want instead of scanning a diagnostic matrix."
	)

	var telemetry := UI.button("Live Telemetry", true)
	telemetry.pressed.connect(func() -> void: navigate_requested.emit("Telemetry"))
	card.add_child(telemetry)

	var location := UI.button("Location & Map")
	location.pressed.connect(func() -> void: navigate_requested.emit("GPS"))
	card.add_child(location)

	var device := UI.button("Camera & Device Tools")
	device.pressed.connect(func() -> void: navigate_requested.emit("Device"))
	card.add_child(device)


func _build_feature_summary() -> void:
	var card := UI.make_card(
		self,
		"AVAILABLE TOOLS",
		"Capabilities are grouped by task. Status and detailed diagnostics live inside each tool page."
	)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(flow)

	for item in [
		["Motion", UI.GOOD],
		["Touch", UI.GOOD],
		["Location", UI.GOOD],
		["Camera", UI.GOOD],
		["Microphone", UI.GOOD],
		["BLE", UI.GOOD],
		["HTTP / WS", UI.GOOD],
		["UDP / OSC", UI.GOOD],
		["AR / NFC probes", UI.WARN],
	]:
		flow.add_child(UI.status_pill(str(item[0]), item[1]))


func _refresh() -> void:
	var build := _read_build_info()
	var sha := str(build.get("git_sha", "LOCAL"))
	if sha.length() > 8:
		sha = sha.left(8)
	_build_value.text = "%s · %s" % [
		str(build.get("version", "0.4.0-dev")),
		sha,
	]

	var platform := OS.get_name()
	var model := OS.get_model_name()
	_platform_value.text = platform if model.is_empty() else "%s · %s" % [platform, model]

	var viewport := get_viewport().get_visible_rect().size
	_viewport_value.text = "%d × %d pt-like" % [int(viewport.x), int(viewport.y)]


func _read_build_info() -> Dictionary:
	const PATH := "res://config/build_info.json"
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
