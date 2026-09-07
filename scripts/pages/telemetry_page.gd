extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

var _service: Node
var _transport: OptionButton
var _address: LineEdit
var _rate: OptionButton
var _status: Label
var _endpoint: Label
var _sent: Label
var _acked: Label
var _rtt: Label
var _log: RichTextLabel
var _start_button: Button


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Live telemetry",
		"Stream runtime diagnostics directly to PowerShell over your LAN or Tailscale. WebSocket is the default; HTTP POST remains available as a fallback."
	)

	_service = get_tree().get_first_node_in_group("ios_lab_telemetry")

	_build_connection_card()
	_build_stats_card()
	_build_payload_card()
	_build_receiver_card()

	if _service == null:
		_status.text = "telemetry service unavailable"
		_start_button.disabled = true
		return

	_service.status_changed.connect(_on_status_changed)
	_service.stats_changed.connect(_on_stats_changed)
	_service.log_line.connect(_append_log)
	_service.receiver_message.connect(_on_receiver_message)
	_restore_local_config()
	_refresh_endpoint_preview()


func _build_connection_card() -> void:
	var card := UI.make_card(
		self,
		"POWERSHELL BRIDGE",
		"Enter the PC address that the iPhone can reach. For Tailscale this is normally the PC's 100.x.x.x address plus port 8787. Nothing is transmitted until you press START STREAM."
	)

	_transport = UI.option_button([
		"WebSocket · recommended",
		"HTTP POST · fallback",
	])
	_transport.item_selected.connect(_on_transport_changed)
	card.add_child(_transport)

	_address = UI.line_edit("100.x.x.x:8787")
	_address.text_changed.connect(func(_value: String) -> void: _refresh_endpoint_preview())
	card.add_child(_address)

	_rate = UI.option_button([
		"1 Hz · low traffic",
		"2 Hz",
		"5 Hz · recommended",
		"10 Hz · dense debug",
	])
	_rate.select(2)
	card.add_child(_rate)

	_endpoint = UI.value_row(card, "Resolved", "—")
	_status = UI.value_row(card, "State", "offline")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	card.add_child(buttons)

	_start_button = UI.button("START STREAM", true)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_toggle_stream)
	buttons.add_child(_start_button)

	var probe := UI.button("SEND PROBE")
	probe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	probe.pressed.connect(_send_probe)
	buttons.add_child(probe)


func _build_stats_card() -> void:
	var card := UI.make_card(
		self,
		"LINK HEALTH",
		"Every packet carries a sequence number. The PowerShell receiver sends an ACK so round-trip time and packet acknowledgement can be checked live."
	)
	_sent = UI.value_row(card, "Sent", "0")
	_acked = UI.value_row(card, "ACK", "0")
	_rtt = UI.value_row(card, "Last RTT", "—")

	_log = UI.terminal_log(180)
	_log.text = "telemetry log ready"
	card.add_child(_log)


func _build_payload_card() -> void:
	var card := UI.make_card(
		self,
		"PAYLOAD · ioslab.telemetry.v1",
		"Snapshots include build identity, current page, FPS, touch events, accelerometer, gravity, gyroscope, magnetometer, latest GPS fix, BLE state, Apple capability probes, battery level and local IP addresses."
	)
	card.add_child(UI.label(
		"Privacy: no Apple ID, UDID, pairing material, clipboard contents, camera frames or microphone audio are included. Telemetry goes only to the endpoint you enter.",
		13,
		UI.MUTED
	))


func _build_receiver_card() -> void:
	var card := UI.make_card(
		self,
		"PC RECEIVER",
		"The repository contains a dependency-free PowerShell receiver. It listens with TcpListener, so it does not require an HTTP URL reservation or administrator rights just to bind the port."
	)

	var command := "pwsh -ExecutionPolicy Bypass -File .\\tools\\Receive-IOSLabTelemetry.ps1 -Port 8787"
	var command_label := UI.code_label(command)
	card.add_child(command_label)

	var copy := UI.button("COPY POWERSHELL COMMAND")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(command)
		_append_log("copied PowerShell receiver command")
	)
	card.add_child(copy)

	card.add_child(UI.label(
		"When the receiver starts, it prints the Tailscale and LAN endpoints it detects. Put the matching host:port above, start the stream, then copy the PowerShell output back into ChatGPT for live diagnosis.",
		13,
		UI.MUTED
	))


func _toggle_stream() -> void:
	if _service == null:
		return

	if _service.is_streaming():
		_service.stop_stream()
		_start_button.text = "START STREAM"
		return

	var mode := "http" if _transport.selected == 1 else "websocket"
	var rate := _selected_rate()
	_service.configure(mode, _address.text, rate)
	_save_local_config()
	_refresh_endpoint_preview()
	if _service.start_stream():
		_start_button.text = "STOP STREAM"


func _send_probe() -> void:
	if _service == null:
		return
	_service.send_probe()


func _on_transport_changed(_index: int) -> void:
	_refresh_endpoint_preview()


func _on_status_changed(state: String, detail: String) -> void:
	_status.text = "%s · %s" % [state.to_upper(), detail]
	_start_button.text = "STOP STREAM" if _service != null and _service.is_streaming() else "START STREAM"


func _on_stats_changed(sent: int, acknowledged: int, last_rtt_ms: int) -> void:
	_sent.text = str(sent)
	_acked.text = str(acknowledged)
	_rtt.text = "%d ms" % last_rtt_ms if last_rtt_ms >= 0 else "—"


func _on_receiver_message(message: String) -> void:
	_append_log("RX · %s" % message.left(260))


func _append_log(line: String) -> void:
	if _log == null:
		return
	var stamp := Time.get_time_string_from_system()
	_log.append_text("\n[%s] %s" % [stamp, line])
	if _log.text.length() > 12000:
		_log.text = _log.text.right(9000)
	_log.scroll_to_line(maxi(_log.get_line_count() - 1, 0))


func _refresh_endpoint_preview() -> void:
	if _endpoint == null:
		return
	var address := _address.text.strip_edges() if _address != null else ""
	if address.is_empty():
		_endpoint.text = "—"
		return

	var mode := "http" if _transport != null and _transport.selected == 1 else "websocket"
	var prefix := "http://" if mode == "http" else "ws://"
	if address.begins_with("http://") or address.begins_with("https://") or address.begins_with("ws://") or address.begins_with("wss://"):
		prefix = ""
	var value := prefix + address
	var scheme := value.find("://")
	var path_start := value.find("/", scheme + 3)
	if path_start == -1:
		value += "/telemetry"
	elif path_start == value.length() - 1:
		value += "telemetry"
	_endpoint.text = value


func _selected_rate() -> float:
	match _rate.selected:
		0:
			return 1.0
		1:
			return 2.0
		3:
			return 10.0
		_:
			return 5.0


func _save_local_config() -> void:
	var data := {
		"address": _address.text.strip_edges(),
		"transport": _transport.selected,
		"rate": _rate.selected,
	}
	var file := FileAccess.open("user://telemetry_receiver.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))


func _restore_local_config() -> void:
	const PATH := "user://telemetry_receiver.json"
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var data := parsed as Dictionary
	_address.text = str(data.get("address", ""))
	_transport.select(clampi(int(data.get("transport", 0)), 0, 1))
	_rate.select(clampi(int(data.get("rate", 2)), 0, 3))
