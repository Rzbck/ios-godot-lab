extends Node

signal http_finished(ok: bool, status_code: int, headers: PackedStringArray, body: String)
signal websocket_state_changed(state: String)
signal websocket_message(text: String)
signal transport_error(message: String)
signal udp_sent(bytes: int)

var _http: HTTPRequest
var _ws := WebSocketPeer.new()
var _last_ws_state := WebSocketPeer.STATE_CLOSED

var _udp := PacketPeerUDP.new()
var _udp_host := ""
var _udp_port := 0

var _osc_udp := PacketPeerUDP.new()
var _osc_host := ""
var _osc_port := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	set_process(true)


func _exit_tree() -> void:
	_reset_udp_peer()
	_reset_osc_peer()


func http_request(url: String, method_name: String, headers: PackedStringArray, body: String) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()

	var method := _method_from_name(method_name)
	var error := _http.request(url, headers, method, body)
	if error != OK:
		transport_error.emit("HTTP request error: %s" % error_string(error))


func websocket_connect(url: String) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()

	_ws = WebSocketPeer.new()
	var error := _ws.connect_to_url(url)
	if error != OK:
		transport_error.emit("WebSocket connect error: %s" % error_string(error))
		return

	_last_ws_state = _ws.get_ready_state()
	websocket_state_changed.emit(_ws_state_name(_last_ws_state))


func websocket_disconnect() -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close(1000, "client disconnect")


func websocket_send_text(text: String) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		transport_error.emit("WebSocket is not open")
		return

	var error := _ws.send_text(text)
	if error != OK:
		transport_error.emit("WebSocket send error: %s" % error_string(error))


func udp_send(host: String, port: int, text: String) -> void:
	if not _ensure_udp_peer(host, port):
		return

	var payload := text.to_utf8_buffer()
	var error := _udp.put_packet(payload)
	if error != OK:
		_reset_udp_peer()
		transport_error.emit("UDP send error: %s" % error_string(error))
	else:
		udp_sent.emit(payload.size())


func osc_send_string(host: String, port: int, address: String, value: String) -> void:
	if not _ensure_osc_peer(host, port):
		return

	var packet := PackedByteArray()
	packet.append_array(_osc_string(address if address.begins_with("/") else "/" + address))
	packet.append_array(_osc_string(",s"))
	packet.append_array(_osc_string(value))

	var error := _osc_udp.put_packet(packet)
	if error != OK:
		_reset_osc_peer()
		transport_error.emit("OSC send error: %s" % error_string(error))
	else:
		udp_sent.emit(packet.size())


func _ensure_udp_peer(host: String, port: int) -> bool:
	var clean_host := host.strip_edges()
	if clean_host.is_empty():
		return false
	if _udp_host == clean_host and _udp_port == port:
		return true

	_reset_udp_peer()
	_udp = PacketPeerUDP.new()
	var error := _udp.connect_to_host(clean_host, port)
	if error != OK:
		transport_error.emit("UDP connect error: %s" % error_string(error))
		return false

	_udp_host = clean_host
	_udp_port = port
	return true


func _ensure_osc_peer(host: String, port: int) -> bool:
	var clean_host := host.strip_edges()
	if clean_host.is_empty():
		return false
	if _osc_host == clean_host and _osc_port == port:
		return true

	_reset_osc_peer()
	_osc_udp = PacketPeerUDP.new()
	var error := _osc_udp.connect_to_host(clean_host, port)
	if error != OK:
		transport_error.emit("OSC/UDP connect error: %s" % error_string(error))
		return false

	_osc_host = clean_host
	_osc_port = port
	return true


func _reset_udp_peer() -> void:
	_udp.close()
	_udp = PacketPeerUDP.new()
	_udp_host = ""
	_udp_port = 0


func _reset_osc_peer() -> void:
	_osc_udp.close()
	_osc_udp = PacketPeerUDP.new()
	_osc_host = ""
	_osc_port = 0


func _process(_delta: float) -> void:
	var state := _ws.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED:
		_ws.poll()
		state = _ws.get_ready_state()

	if state != _last_ws_state:
		_last_ws_state = state
		websocket_state_changed.emit(_ws_state_name(state))

	if state == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			var packet := _ws.get_packet()
			websocket_message.emit(packet.get_string_from_utf8())


func _on_http_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS
	http_finished.emit(ok, response_code, headers, body.get_string_from_utf8())


func _method_from_name(method_name: String) -> int:
	match method_name.to_upper():
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"DELETE":
			return HTTPClient.METHOD_DELETE
		"HEAD":
			return HTTPClient.METHOD_HEAD
		_:
			return HTTPClient.METHOD_GET


func _ws_state_name(state: int) -> String:
	match state:
		WebSocketPeer.STATE_CONNECTING:
			return "connecting"
		WebSocketPeer.STATE_OPEN:
			return "open"
		WebSocketPeer.STATE_CLOSING:
			return "closing"
		WebSocketPeer.STATE_CLOSED:
			return "closed"
		_:
			return "unknown"


func _osc_string(value: String) -> PackedByteArray:
	var bytes := value.to_utf8_buffer()
	bytes.append(0)
	while bytes.size() % 4 != 0:
		bytes.append(0)
	return bytes
