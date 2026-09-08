extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

var _router: Node

var _profile: OptionButton
var _rate: OptionButton
var _status: Label
var _sent: Label
var _errors: Label
var _start_button: Button

var _shared_host: LineEdit

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
	custom_minimum_size.x = 0
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Live Output",
		"Send live iPhone data to TouchDesigner, OSC, UDP, WebSocket or HTTP."
	)

	_router = get_tree().get_first_node_in_group("ios_lab_router")
	_build_stream_card()
	_build_destination_card()
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
	_bind_persistence()


func _build_stream_card() -> void:
	var card := UI.make_card(
		self,
		"LIVE DATA",
		"Choose what to send and how often. Several outputs can run at the same time."
	)

	card.add_child(_field_label("DATA PROFILE"))
	_profile = UI.option_button(["All", "Motion", "Location", "Touch", "Device"])
	card.add_child(_profile)

	card.add_child(_field_label("SAMPLE RATE"))
	_rate = UI.option_button(["1 Hz", "5 Hz", "10 Hz", "30 Hz"])
	_rate.select(2)
	card.add_child(_rate)

	_status = UI.value_row(card, "State", "offline")
	_sent = UI.value_row(card, "Packets", "0")
	_errors = UI.value_row(card, "Errors", "0")

	_start_button = UI.button("START LIVE OUTPUT", true)
	_start_button.pressed.connect(_toggle_router)
	card.add_child(_start_button)


func _build_destination_card() -> void:
	var card := UI.make_card(
		self,
		"DESTINATION",
		"Enter the Tailscale or LAN host once, then fill the normal TouchDesigner routes automatically."
	)

	card.add_child(_field_label("HOST"))
	_shared_host = UI.line_edit("100.x.x.x")
	card.add_child(_shared_host)

	var preset := UI.button("FILL TOUCHDESIGNER ROUTES", false)
	preset.pressed.connect(_apply_touchdesigner_preset)
	card.add_child(preset)


func _build_ws_card() -> void:
	var card := UI.make_card(
		self,
		"WEBSOCKET",
		"Continuous reliable JSON stream."
	)
	_ws_enabled = _switch("WebSocket / WSS")
	card.add_child(_ws_enabled)
	card.add_child(_field_label("SERVER URL"))
	_ws_url = UI.line_edit("ws://100.x.x.x:9001/ioslab")
	_ws_url.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	card.add_child(_ws_url)


func _build_udp_card() -> void:
	var card := UI.make_card(
		self,
		"UDP JSON",
		"One UTF-8 JSON datagram per sample. Use Motion for the smallest high-rate packets."
	)
	_udp_enabled = _switch("UDP JSON")
	card.add_child(_udp_enabled)

	card.add_child(_field_label("DESTINATION HOST"))
	_udp_host = UI.line_edit("100.x.x.x")
	card.add_child(_udp_host)

	card.add_child(_field_label("PORT"))
	_udp_port = UI.line_edit("7000")
	_udp_port.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	card.add_child(_udp_port)


func _build_osc_card() -> void:
	var card := UI.make_card(
		self,
		"OSC",
		"Sends the selected snapshot as one OSC string at <prefix>/json."
	)
	_osc_enabled = _switch("OSC")
	card.add_child(_osc_enabled)

	card.add_child(_field_label("DESTINATION HOST"))
	_osc_host = UI.line_edit("100.x.x.x")
	card.add_child(_osc_host)

	card.add_child(_field_label("PORT"))
	_osc_port = UI.line_edit("7001")
	_osc_port.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	card.add_child(_osc_port)

	card.add_child(_field_label("OSC PREFIX"))
	_osc_prefix = UI.line_edit("/ioslab")
	card.add_child(_osc_prefix)


func _build_http_card() -> void:
	var card := UI.make_card(
		self,
		"HTTP POST",
		"POST snapshots as JSON. Better for diagnostics/recording than high-rate motion."
	)
	_http_enabled = _switch("HTTP / HTTPS")
	card.add_child(_http_enabled)
	card.add_child(_field_label("ENDPOINT"))
	_http_url = UI.line_edit("http://100.x.x.x:9001/data")
	_http_url.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	card.add_child(_http_url)


func _build_format_card() -> void:
	var card := UI.make_card(
		self,
		"FORMAT",
		"Schema: ioslab.live.v1. All includes motion, touch, GPS, track, device, Bluetooth, capabilities and camera diagnostics."
	)
	card.add_child(UI.label(
		"Motion = accelerometer, gravity, gyroscope and magnetometer. Location = GPS plus distance, elevation, duration and speed metrics.",
		13,
		UI.MUTED
	))


func _field_label(text_value: String) -> Label:
	return UI.single_line_label(text_value, 11, UI.MUTED)


func _switch(text_value: String) -> CheckButton:
	var node := CheckButton.new()
	node.text = text_value
	node.clip_text = true
	node.custom_minimum_size = Vector2(0, 48)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", 16)
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


func _apply_touchdesigner_preset() -> void:
	var host := _shared_host.text.strip_edges()
	if host.is_empty():
		host = _infer_shared_host(_collect_config())
	if host.is_empty():
		_status.text = "ENTER HOST"
		return

	_shared_host.text = host
	_ws_url.text = "ws://%s:9001/ioslab" % host
	_udp_host.text = host
	_udp_port.text = "7000"
	_osc_host.text = host
	_osc_port.text = "7001"
	_osc_prefix.text = "/ioslab"
	_http_url.text = "http://%s:9001/data" % host
	_save_current_config()


func _collect_config() -> Dictionary:
	return {
		"shared_host": _shared_host.text.strip_edges(),
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


func _save_current_config() -> void:
	if _shared_host == null:
		return
	_save_config(_collect_config())


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

	var shared := str(config.get("shared_host", "")).strip_edges()
	if shared.is_empty():
		shared = _infer_shared_host(config)
	_shared_host.text = shared


func _bind_persistence() -> void:
	_profile.item_selected.connect(_on_config_index_changed)
	_rate.item_selected.connect(_on_config_index_changed)

	for toggle in [_ws_enabled, _udp_enabled, _osc_enabled, _http_enabled]:
		toggle.toggled.connect(_on_config_toggle_changed)

	for field in [_shared_host, _ws_url, _udp_host, _udp_port, _osc_host, _osc_port, _osc_prefix, _http_url]:
		field.focus_exited.connect(_on_config_focus_exited)
		field.text_submitted.connect(_on_config_text_submitted)


func _on_config_index_changed(_index: int) -> void:
	_save_current_config()


func _on_config_toggle_changed(_pressed: bool) -> void:
	_save_current_config()


func _on_config_focus_exited() -> void:
	_save_current_config()


func _on_config_text_submitted(_text: String) -> void:
	_save_current_config()


func _infer_shared_host(config: Dictionary) -> String:
	for key in ["shared_host", "udp_host", "osc_host"]:
		var value := str(config.get(key, "")).strip_edges()
		if not value.is_empty():
			return value

	for key in ["ws_url", "http_url"]:
		var host := _host_from_url(str(config.get(key, "")))
		if not host.is_empty():
			return host
	return ""


func _host_from_url(value: String) -> String:
	var result := value.strip_edges()
	for prefix in ["ws://", "wss://", "http://", "https://"]:
		if result.begins_with(prefix):
			result = result.substr(prefix.length())
			break

	var slash := result.find("/")
	if slash >= 0:
		result = result.left(slash)
	if result.count(":") == 1:
		var colon := result.rfind(":")
		if colon > 0:
			result = result.left(colon)
	return result
