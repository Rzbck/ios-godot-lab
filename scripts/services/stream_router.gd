extends Node

signal status_changed(state: String, detail: String)
signal stats_changed(sent_packets: int, transport_errors: int, last_send_unix_ms: int)

const NetworkClient = preload("res://scripts/services/network_client.gd")
const SCHEMA := "ioslab.live.v1"

var _client: Node
var _telemetry: Node

var _running := false
var _profile := "all"
var _rate_hz := 10.0
var _send_accumulator := 0.0

var _ws_enabled := false
var _ws_url := ""
var _ws_open := false
var _ws_reconnect_timer := 0.0
var _ws_reconnect_attempt := 0

var _udp_enabled := false
var _udp_host := ""
var _udp_port := 7000

var _osc_enabled := false
var _osc_host := ""
var _osc_port := 7001
var _osc_prefix := "/ioslab"

var _http_enabled := false
var _http_url := ""
var _http_in_flight := false

var _sent_packets := 0
var _transport_errors := 0
var _last_send_unix_ms := 0
var _status := "offline"
var _detail := "router stopped"


func _ready() -> void:
	add_to_group("ios_lab_router")
	_client = NetworkClient.new()
	add_child(_client)
	_client.websocket_state_changed.connect(_on_ws_state)
	_client.websocket_message.connect(_on_ws_message)
	_client.transport_error.connect(_on_transport_error)
	_client.http_finished.connect(_on_http_finished)
	_telemetry = get_tree().get_first_node_in_group("ios_lab_telemetry")
	set_process(true)


func configure(config: Dictionary) -> void:
	_profile = str(config.get("profile", "all")).to_lower()
	_rate_hz = clampf(float(config.get("rate_hz", 10.0)), 1.0, 30.0)

	_ws_enabled = bool(config.get("ws_enabled", false))
	_ws_url = _normalize_ws(str(config.get("ws_url", "")))

	_udp_enabled = bool(config.get("udp_enabled", false))
	_udp_host = str(config.get("udp_host", "")).strip_edges()
	_udp_port = clampi(int(config.get("udp_port", 7000)), 1, 65535)

	_osc_enabled = bool(config.get("osc_enabled", false))
	_osc_host = str(config.get("osc_host", "")).strip_edges()
	_osc_port = clampi(int(config.get("osc_port", 7001)), 1, 65535)
	_osc_prefix = str(config.get("osc_prefix", "/ioslab")).strip_edges()
	if not _osc_prefix.begins_with("/"):
		_osc_prefix = "/" + _osc_prefix

	_http_enabled = bool(config.get("http_enabled", false))
	_http_url = _normalize_http(str(config.get("http_url", "")))


func start() -> bool:
	if not _has_any_valid_route():
		_emit_status("error", "no valid destination enabled")
		return false

	_running = true
	_send_accumulator = 0.0
	_sent_packets = 0
	_transport_errors = 0
	_last_send_unix_ms = 0
	_http_in_flight = false

	if _ws_enabled and not _ws_url.is_empty():
		_connect_ws()
	else:
		_emit_status("live", "live router active")
	_send_once()
	return true


func stop() -> void:
	_running = false
	_http_in_flight = false
	_ws_reconnect_timer = 0.0
	_ws_reconnect_attempt = 0
	_ws_open = false
	_client.websocket_disconnect()
	_emit_status("offline", "router stopped")


func is_running() -> bool:
	return _running


func get_status() -> Dictionary:
	return {
		"running": _running,
		"state": _status,
		"detail": _detail,
		"profile": _profile,
		"rate_hz": _rate_hz,
		"sent_packets": _sent_packets,
		"transport_errors": _transport_errors,
		"last_send_unix_ms": _last_send_unix_ms,
		"ws_open": _ws_open,
	}


func _process(delta: float) -> void:
	if not _running:
		return

	if _ws_enabled and not _ws_open and _ws_reconnect_timer > 0.0:
		_ws_reconnect_timer -= delta
		if _ws_reconnect_timer <= 0.0:
			_connect_ws()

	_send_accumulator += delta
	var interval := 1.0 / maxf(_rate_hz, 1.0)
	if _send_accumulator < interval:
		return
	_send_accumulator = fmod(_send_accumulator, interval)
	_send_once()


func _send_once() -> void:
	if _telemetry == null:
		_telemetry = get_tree().get_first_node_in_group("ios_lab_telemetry")
	if _telemetry == null or not _telemetry.has_method("get_live_state"):
		_emit_status("error", "live state source unavailable")
		return

	var source := _telemetry.call("get_live_state") as Dictionary
	var packet := _profile_packet(source)
	var text := JSON.stringify(packet)
	var sent_any := false

	if _ws_enabled and _ws_open:
		_client.websocket_send_text(text)
		sent_any = true

	if _udp_enabled and not _udp_host.is_empty():
		_client.udp_send(_udp_host, _udp_port, text)
		sent_any = true

	if _osc_enabled and not _osc_host.is_empty():
		_client.osc_send_string(_osc_host, _osc_port, _osc_prefix + "/json", text)
		sent_any = true

	if _http_enabled and not _http_url.is_empty() and not _http_in_flight:
		_http_in_flight = true
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
			"X-IOSLab-Schema: %s" % SCHEMA,
		])
		_client.http_request(_http_url, "POST", headers, text)
		sent_any = true

	if sent_any:
		_sent_packets += 1
		_last_send_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
		stats_changed.emit(_sent_packets, _transport_errors, _last_send_unix_ms)
		if _status != "live":
			_emit_status("live", "streaming live iPhone data")


func _profile_packet(source: Dictionary) -> Dictionary:
	var packet := {
		"schema": SCHEMA,
		"type": "live",
		"sent_unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"profile": _profile,
		"build": source.get("build", {}),
		"app": source.get("app", {}),
	}

	match _profile:
		"motion":
			packet["sensors"] = source.get("sensors", {})
		"location":
			packet["location"] = source.get("location", {})
			packet["track"] = source.get("track", {})
		"touch":
			packet["touch"] = source.get("touch", {})
		"device":
			packet["device"] = source.get("device", {})
			packet["capabilities"] = source.get("capabilities", {})
			packet["bluetooth"] = source.get("bluetooth", {})
		_:
			for key in ["device", "sensors", "touch", "location", "track", "bluetooth", "capabilities"]:
				packet[key] = source.get(key, {})
	return packet


func _connect_ws() -> void:
	if not _running or not _ws_enabled or _ws_url.is_empty():
		return
	_emit_status("connecting", "WebSocket → %s" % _ws_url)
	_client.websocket_connect(_ws_url)


func _schedule_ws_reconnect() -> void:
	if not _running or not _ws_enabled:
		return
	_ws_reconnect_attempt += 1
	var delay := minf(pow(2.0, minf(float(_ws_reconnect_attempt - 1), 4.0)), 15.0)
	_ws_reconnect_timer = delay
	_emit_status("reconnecting", "WebSocket retry in %.0f s" % delay)


func _on_ws_state(state: String) -> void:
	_ws_open = state == "open"
	if not _running:
		return
	match state:
		"open":
			_ws_reconnect_attempt = 0
			_ws_reconnect_timer = 0.0
			_emit_status("live", "WebSocket connected")
		"closed":
			_schedule_ws_reconnect()
		"connecting":
			_emit_status("connecting", "WebSocket connecting")


func _on_ws_message(_text: String) -> void:
	pass


func _on_http_finished(ok: bool, status_code: int, _headers: PackedStringArray, _body: String) -> void:
	_http_in_flight = false
	if not ok or status_code < 200 or status_code >= 300:
		_transport_errors += 1
		stats_changed.emit(_sent_packets, _transport_errors, _last_send_unix_ms)
		_emit_status("degraded", "HTTP status %d" % status_code)


func _on_transport_error(message: String) -> void:
	_transport_errors += 1
	_http_in_flight = false
	stats_changed.emit(_sent_packets, _transport_errors, _last_send_unix_ms)
	if _running:
		_emit_status("degraded", message.left(100))


func _emit_status(state: String, detail: String) -> void:
	if state == _status and detail == _detail:
		return
	_status = state
	_detail = detail
	status_changed.emit(state, detail)


func _has_any_valid_route() -> bool:
	return (
		(_ws_enabled and not _ws_url.is_empty())
		or (_udp_enabled and not _udp_host.is_empty())
		or (_osc_enabled and not _osc_host.is_empty())
		or (_http_enabled and not _http_url.is_empty())
	)


func _normalize_ws(value: String) -> String:
	var result := value.strip_edges()
	if result.is_empty():
		return ""
	if not result.begins_with("ws://") and not result.begins_with("wss://"):
		result = "ws://" + result
	return result


func _normalize_http(value: String) -> String:
	var result := value.strip_edges()
	if result.is_empty():
		return ""
	if not result.begins_with("http://") and not result.begins_with("https://"):
		result = "http://" + result
	return result
