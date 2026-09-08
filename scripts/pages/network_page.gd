extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

var _router: Node

var _profile: OptionButton
var _rate: OptionButton
var _status: Label
var _sent: Label
var _errors: Label
var _start_button: Button

var _ws_enabled: CheckButton
var _ws_url: LineEdit

var _udp_enabled: CheckButton
var _udp_host: LineEdit
var _udp_port: LineEdit

var _osc_enabled: CheckButton
var _osc_host: LineEdit
var _osc_port: LineEdit
var _osc_prefix: LineEdit

var _http_enabled: CheckButton
var _http_url: LineEdit


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Live Output",
		"Route real iPhone data continuously to creative tools, servers or recorders. No manual message typing is required."
	)

	_router = get_tree().get_first_node_in_group("ios_lab_router")
	_build_stream_card()
	_build_ws_card()
	_build_udp_card()
	_build_osc_card()
	_build_http_card()
	_build_format_card()

	if _router == null:
		_status.text = "router unavailable"
		_start_button.disabled = true
		return

	_router.status_changed.connect(_on_router_status)
	_router.stats_changed.connect(_on_router_stats)
	_restore_config()


func _build_stream_card() -> void:
	var card := UI.make_card(
		self,
		"LIVE DATA ROUTER",
		"Choose a data profile and sample rate. Enabled outputs run at the same time, so one iPhone can feed TouchDesigner, OSC and a recorder simultaneously."
	)

	_profile = UI.option_button([
		"All · full device snapshot",
		"Motion · accelerometer / gravity / gyro / magnetometer",
		"Location · GPS + track metrics",
		"Touch · touch / drag",
		"Device · battery / BLE / capabilities",
	])
	card.add_child(_profile)

	_rate = UI.option_button([
		"1 Hz",
		"5 Hz",
		"10 Hz",
		"30 Hz · motion / realtime",
	])
	_rate.select(2)
	card.add_child(_rate)

	_status = UI.value_row(card, "State", "offline")
	_sent = UI.value_row(card, "Packets", "0")
	_errors = UI.value_row(card, "Errors", "0")

	_start_button = UI.button("START LIVE OUTPUT", true)
	_start_button.pressed.connect(_toggle_router)
	card.add_child(_start_button)


func _build_ws_card() -> void:
	var card := UI.make_card(
		self,
		"WEBSOCKET / WSS",
		"Continuous JSON stream. Ideal for a custom server, TouchDesigner WebSocket DAT or a Tailscale peer."
	)
	_ws_enabled = _switch("Enable WebSocket")
	card.add_child(_ws_enabled)
	_ws_url = UI.line_edit("100.x.x.x:9001 or wss://host/path")
	card.add_child(_ws_url)


func _build_udp_card() -> void:
	var card := UI.make_card(
		self,
		"UDP · JSON",
		"One UTF-8 JSON datagram per sample. Low overhead and simple to receive in TouchDesigner, Python or another realtime process."
	)
	_udp_enabled = _switch("Enable UDP JSON")
	card.add_child(_udp_enabled)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	_udp_host = UI.line_edit("100.x.x.x")
	_udp_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_udp_host)
	_udp_port = UI.line_edit("7000")
	_udp_port.custom_minimum_size.x = 90
	row.add_child(_udp_port)


func _build_osc_card() -> void:
	var card := UI.make_card(
		self,
		"OSC",
		"Sends the selected live JSON snapshot as one OSC string at <prefix>/json. This is easy to parse in TouchDesigner or another OSC receiver."
	)
	_osc_enabled = _switch("Enable OSC")
	card.add_child(_osc_enabled)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	_osc_host = UI.line_edit("100.x.x.x")
	_osc_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_osc_host)
	_osc_port = UI.line_edit("7001")
	_osc_port.custom_minimum_size.x = 90
	row.add_child(_osc_port)

	_osc_prefix = UI.line_edit("/ioslab")
	card.add_child(_osc_prefix)


func _build_http_card() -> void:
	var card := UI.make_card(
		self,
		"HTTP / HTTPS",
		"POST the selected live snapshot as JSON. Best for APIs and recorders that do not expose WebSocket or UDP."
	)
	_http_enabled = _switch("Enable HTTP POST")
	card.add_child(_http_enabled)
	_http_url = UI.line_edit("https://host/api/iphone or http://100.x.x.x:9002/data")
	card.add_child(_http_url)


func _build_format_card() -> void:
	var card := UI.make_card(
		self,
		"DATA FORMAT",
		"WebSocket, UDP and HTTP send ioslab.live.v1 JSON. OSC sends the same JSON as one string message at <prefix>/json."
	)
	card.add_child(UI.label(
		"Profiles are only filters; the source is the same canonical live state used by telemetry. GPS track metrics include distance, elevation gain/loss, duration, moving time, average speed and max speed.",
		13,
		UI.MUTED
	))


func _switch(text_value: String) -> CheckButton:
	var node := CheckButton.new()
	node.text = text_value
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size", 15)
	node.add_theme_color_override("font_color", UI.TEXT)
	node.add_theme_color_override("font_pressed_color", UI.ACCENT)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	return node


func _toggle_router() -> void:
	if _router == null:
		return

	if _router.is_running():
		_router.stop()
		_start_button.text = "START LIVE OUTPUT"
		return

	var config := _collect_config()
	_router.configure(config)
	_save_config(config)
	if _router.start():
		_start_button.text = "STOP LIVE OUTPUT"


func _collect_config() -> Dictionary:
	return {
		"profile": _selected_profile(),
		"rate_hz": _selected_rate(),
		"ws_enabled": _ws_enabled.button_pressed,
		"ws_url": _ws_url.text.strip_edges(),
		"udp_enabled": _udp_enabled.button_pressed,
		"udp_host": _udp_host.text.strip_edges(),
		"udp_port": _udp_port.text.to_int(),
		"osc_enabled": _osc_enabled.button_pressed,
		"osc_host": _osc_host.text.strip_edges(),
		"osc_port": _osc_port.text.to_int(),
		"osc_prefix": _osc_prefix.text.strip_edges(),
		"http_enabled": _http_enabled.button_pressed,
		"http_url": _http_url.text.strip_edges(),
	}


func _selected_profile() -> String:
	match _profile.selected:
		1:
			return "motion"
		2:
			return "location"
		3:
			return "touch"
		4:
			return "device"
		_:
			return "all"


func _selected_rate() -> float:
	match _rate.selected:
		0:
			return 1.0
		1:
			return 5.0
		3:
			return 30.0
		_:
			return 10.0


func _on_router_status(state: String, _detail: String) -> void:
	match state:
		"live":
			_status.text = "LIVE"
		"connecting":
			_status.text = "CONNECTING"
		"reconnecting":
			_status.text = "RETRYING"
		"degraded":
			_status.text = "DEGRADED"
		"error":
			_status.text = "ERROR"
		_:
			_status.text = state.to_upper()
	_start_button.text = "STOP LIVE OUTPUT" if _router != null and _router.is_running() else "START LIVE OUTPUT"


func _on_router_stats(sent_packets: int, transport_errors: int, _last_send_unix_ms: int) -> void:
	_sent.text = str(sent_packets)
	_errors.text = str(transport_errors)


func _save_config(config: Dictionary) -> void:
	var file := FileAccess.open("user://live_router.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(config))


func _restore_config() -> void:
	const PATH := "user://live_router.json"
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var config := parsed as Dictionary

	var profiles := ["all", "motion", "location", "touch", "device"]
	var profile := str(config.get("profile", "all"))
	_profile.select(profiles.find(profile) if profiles.has(profile) else 0)

	var rate := float(config.get("rate_hz", 10.0))
	_rate.select(0 if rate <= 1.0 else 1 if rate <= 5.0 else 2 if rate <= 10.0 else 3)

	_ws_enabled.button_pressed = bool(config.get("ws_enabled", false))
	_ws_url.text = str(config.get("ws_url", ""))
	_udp_enabled.button_pressed = bool(config.get("udp_enabled", false))
	_udp_host.text = str(config.get("udp_host", ""))
	_udp_port.text = str(config.get("udp_port", 7000))
	_osc_enabled.button_pressed = bool(config.get("osc_enabled", false))
	_osc_host.text = str(config.get("osc_host", ""))
	_osc_port.text = str(config.get("osc_port", 7001))
	_osc_prefix.text = str(config.get("osc_prefix", "/ioslab"))
	_http_enabled.button_pressed = bool(config.get("http_enabled", false))
	_http_url.text = str(config.get("http_url", ""))
