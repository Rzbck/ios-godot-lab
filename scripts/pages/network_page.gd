extends VBoxContainer

const UI = preload("res://scripts/ui.gd")
const NetworkClient = preload("res://scripts/services/network_client.gd")

var _client: Node

var _http_url: LineEdit
var _http_method: OptionButton
var _http_headers: TextEdit
var _http_body: TextEdit
var _http_response: TextEdit

var _ws_url: LineEdit
var _ws_state: Label
var _ws_message: TextEdit
var _ws_log: TextEdit

var _udp_host: LineEdit
var _udp_port: LineEdit
var _udp_payload: TextEdit

var _osc_address: LineEdit
var _osc_value: LineEdit
var _transport_status: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Network I/O",
		"Generic HTTP(S), WebSocket/WSS, UDP and OSC string output. Use a LAN address, Tailscale address or public endpoint that your iPhone can reach."
	)

	_client = NetworkClient.new()
	add_child(_client)
	_client.http_finished.connect(_on_http_finished)
	_client.websocket_state_changed.connect(_on_ws_state)
	_client.websocket_message.connect(_on_ws_message)
	_client.transport_error.connect(_on_transport_error)
	_client.udp_sent.connect(_on_udp_sent)

	var status := UI.make_card(
		self,
		"TRANSPORT STATUS",
		"Local-network access may trigger an iOS permission prompt. This personal LAB build also allows plain HTTP/WS so you can reach arbitrary test endpoints; prefer HTTPS/WSS outside a trusted network."
	)
	_transport_status = UI.value_row(status, "Last event", "idle")

	_build_http_card()
	_build_websocket_card()
	_build_udp_card()

	var td := UI.make_card(
		self,
		"TOUCHDESIGNER",
		"Point these tools at your computer's reachable IP. WebSocket/HTTP work with matching TouchDesigner server components; UDP/OSC are useful for DAT/CHOP workflows and simple control messages."
	)
	td.add_child(UI.label(
		"Nothing is hard-coded: host, port, path, headers and payload stay editable so the same app can connect to SIGNAL, TouchDesigner, a local Python service, Tailscale peers or web APIs.",
		14,
		UI.MUTED
	))


func _build_http_card() -> void:
	var card := UI.make_card(
		self,
		"HTTP / HTTPS",
		"Send arbitrary requests. Use JSON, text or any body accepted by the target server."
	)

	_http_url = UI.line_edit("https://example.net/api or http://192.168.x.x:port/path")
	card.add_child(_http_url)

	_http_method = OptionButton.new()
	for method in ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]:
		_http_method.add_item(method)
	_http_method.custom_minimum_size.y = 48
	card.add_child(_http_method)

	_http_headers = UI.text_edit("One header per line\nContent-Type: application/json", 90)
	card.add_child(_http_headers)

	_http_body = UI.text_edit('{"hello":"iphone"}', 110)
	card.add_child(_http_body)

	var send := UI.button("SEND HTTP REQUEST", true)
	send.pressed.connect(_send_http)
	card.add_child(send)

	_http_response = UI.text_edit("", 180)
	_http_response.editable = false
	_http_response.placeholder_text = "Response will appear here."
	card.add_child(_http_response)


func _build_websocket_card() -> void:
	var card := UI.make_card(
		self,
		"WEBSOCKET / WSS",
		"Connect once, then send and receive UTF-8 text messages."
	)

	_ws_url = UI.line_edit("ws://192.168.x.x:port or wss://example.net/socket")
	card.add_child(_ws_url)

	_ws_state = UI.value_row(card, "State", "closed")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	card.add_child(buttons)

	var connect_button := UI.button("CONNECT", true)
	connect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_button.pressed.connect(_connect_ws)
	buttons.add_child(connect_button)

	var disconnect_button := UI.button("DISCONNECT")
	disconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disconnect_button.pressed.connect(_client.websocket_disconnect)
	buttons.add_child(disconnect_button)

	_ws_message = UI.text_edit('{"type":"ping"}', 90)
	card.add_child(_ws_message)

	var send := UI.button("SEND WS TEXT")
	send.pressed.connect(_send_ws)
	card.add_child(send)

	_ws_log = UI.text_edit("", 170)
	_ws_log.editable = false
	_ws_log.placeholder_text = "WebSocket events and incoming messages."
	card.add_child(_ws_log)


func _build_udp_card() -> void:
	var card := UI.make_card(
		self,
		"UDP / OSC",
		"Raw UDP is useful for minimal low-latency messages. OSC sends one standard string argument to an OSC address."
	)

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	card.add_child(host_row)

	_udp_host = UI.line_edit("192.168.x.x")
	_udp_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(_udp_host)

	_udp_port = UI.line_edit("7000")
	_udp_port.custom_minimum_size.x = 95
	host_row.add_child(_udp_port)

	_udp_payload = UI.text_edit('{"value":1}', 90)
	card.add_child(_udp_payload)

	var raw := UI.button("SEND RAW UDP", true)
	raw.pressed.connect(_send_udp)
	card.add_child(raw)

	card.add_child(UI.label("OSC string message", 14, UI.MUTED))

	_osc_address = UI.line_edit("/iphone/value")
	card.add_child(_osc_address)
	_osc_value = UI.line_edit("hello")
	card.add_child(_osc_value)

	var osc := UI.button("SEND OSC STRING")
	osc.pressed.connect(_send_osc)
	card.add_child(osc)


func _send_http() -> void:
	var url := _http_url.text.strip_edges()
	if url.is_empty():
		_transport_status.text = "HTTP URL is empty"
		return

	var headers := PackedStringArray()
	for line in _http_headers.text.split("\n"):
		var value := line.strip_edges()
		if not value.is_empty():
			headers.append(value)

	var method := _http_method.get_item_text(_http_method.selected)
	_transport_status.text = "HTTP %s → %s" % [method, url]
	_client.http_request(url, method, headers, _http_body.text)


func _connect_ws() -> void:
	var url := _ws_url.text.strip_edges()
	if url.is_empty():
		_transport_status.text = "WebSocket URL is empty"
		return
	_append_ws_log("CONNECT → %s" % url)
	_client.websocket_connect(url)


func _send_ws() -> void:
	_client.websocket_send_text(_ws_message.text)
	_append_ws_log("TX: %s" % _ws_message.text)


func _send_udp() -> void:
	var port := _udp_port.text.to_int()
	if port <= 0 or port > 65535:
		_transport_status.text = "invalid UDP port"
		return
	_client.udp_send(_udp_host.text.strip_edges(), port, _udp_payload.text)


func _send_osc() -> void:
	var port := _udp_port.text.to_int()
	if port <= 0 or port > 65535:
		_transport_status.text = "invalid OSC/UDP port"
		return
	_client.osc_send_string(
		_udp_host.text.strip_edges(),
		port,
		_osc_address.text.strip_edges(),
		_osc_value.text
	)


func _on_http_finished(ok: bool, status_code: int, headers: PackedStringArray, body: String) -> void:
	_transport_status.text = "HTTP %d · %s" % [status_code, "transport OK" if ok else "transport failed"]
	var header_text := "\n".join(headers)
	_http_response.text = "STATUS: %d\n\n%s\n\n%s" % [status_code, header_text, body]
	if _http_response.text.length() > 12000:
		_http_response.text = _http_response.text.left(12000) + "\n… truncated …"


func _on_ws_state(state: String) -> void:
	_ws_state.text = state
	_transport_status.text = "WebSocket: %s" % state
	_append_ws_log("STATE: %s" % state)


func _on_ws_message(text: String) -> void:
	_append_ws_log("RX: %s" % text)


func _on_transport_error(message: String) -> void:
	_transport_status.text = message
	_append_ws_log("ERROR: %s" % message)


func _on_udp_sent(bytes: int) -> void:
	_transport_status.text = "UDP/OSC sent · %d bytes" % bytes


func _append_ws_log(line: String) -> void:
	var next := _ws_log.text + ("" if _ws_log.text.is_empty() else "\n") + line
	if next.length() > 9000:
		next = next.right(9000)
	_ws_log.text = next
