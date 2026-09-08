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
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Telemetry",
		"Stream diagnostics to your PC over Tailscale or LAN. Session files are written by the PowerShell receiver."
	)

	_service = get_tree().get_first_node_in_group("ios_lab_telemetry")
	_build_connection_card()
	_build_stats_card()
	_build_receiver_card()

	if _service == null:
		_status.text = "unavailable"
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
		"RECEIVER",
		"Enter the address your iPhone can reach. A Tailscale address normally looks like 100.x.x.x:8787."
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
		"1 Hz · light",
		"2 Hz · normal",
		"5 Hz · recommended",
		"10 Hz · dense capture",
	])
	_rate.select(2)
	card.add_child(_rate)

	_endpoint = UI.value_row(card, "Endpoint", "—")
	_status = UI.value_row(card, "State", "offline")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	card.add_child(buttons)

	_start_button = UI.button("Start Stream", true)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_toggle_stream)
	buttons.add_child(_start_button)

	var probe := UI.button("Send Probe")
	probe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	probe.pressed.connect(_send_probe)
	buttons.add_child(probe)


func _build_stats_card() -> void:
	var card := UI.make_card(
		self,
		"LINK HEALTH",
		"ACK and RTT confirm that packets actually reach the PC receiver."
	)
	_sent = UI.value_row(card, "Sent", "0")
	_acked = UI.value_row(card, "ACK", "0")
	_rtt = UI.value_row(card, "Last RTT", "—")

	_log = UI.terminal_log(150)
	_log.text = "ready"
	card.add_child(_log)


func _build_receiver_card() -> void:
	var card := UI.make_card(
		self,
		"POWERSHELL RECEIVER",
		"Stop the receiver with Ctrl+C to finalize session-summary.txt. The raw capture remains available if we need deeper evidence."
	)

	var command := "pwsh -ExecutionPolicy Bypass -File .\\tools\\Receive-IOSLabTelemetry.ps1 -Port 8787"
	card.add_child(UI.code_label(command))

	var copy := UI.button("Copy Receiver Command")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(command)
		_append_log("receiver command copied")
	)
	card.add_child(copy)

	card.add_child(UI.label(
		"Privacy: no Apple Account, UDID, signing material, clipboard contents, camera frames or microphone audio are transmitted.",
		13,
		UI.MUTED
	))


func _toggle_stream() -> void:
	if _service == null:
		return

	if _service.is_streaming():
		_service.stop_stream()
		_start_button.text = "Start Stream"
		return

	var mode := "http" if _transport.selected == 1 else "websocket"
	_service.configure(mode, _address.text, _selected_rate())
	_save_local_config()
	_refresh_endpoint_preview()
	if _service.start_stream():
		_start_button.text = "Stop Stream"


func _send_probe() -> void:
	if _service != null:
		_service.send_probe()


func _on_transport_changed(_index: int) -> void:
	_refresh_endpoint_preview()


func _on_status_changed(state: String, detail: String) -> void:
	# Keep the visible row fixed-width and fixed-height. Detail belongs in the log.
	_status.text = state.to_upper()
	_append_log("%s · %s" % [state.to_upper(), detail])
	_start_button.text = "Stop Stream" if _service != null and _service.is_streaming() else "Start Stream"


func _on_stats_changed(sent: int, acknowledged: int, last_rtt_ms: int) -> void:
	_sent.text = str(sent)
	_acked.text = str(acknowledged)
	_rtt.text = "%d ms" % last_rtt_ms if last_rtt_ms >= 0 else "—"


func _on_receiver_message(message: String) -> void:
	_append_log("RX · %s" % message.left(180))


func _append_log(line: String) -> void:
	if _log == null:
		return
	var stamp := Time.get_time_string_from_system()
	_log.append_text("\n[%s] %s" % [stamp, line])
	if _log.text.length() > 8000:
		_log.text = _log.text.right(6000)
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
