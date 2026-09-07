extends Node

signal status_changed(state: String, detail: String)
signal stats_changed(sent: int, acknowledged: int, last_rtt_ms: int)
signal log_line(line: String)
signal receiver_message(message: String)

const NetworkClient = preload("res://scripts/services/network_client.gd")
const SCHEMA := "ioslab.telemetry.v1"
const MAX_EVENT_QUEUE := 32
const MAX_PENDING_ACKS := 64

var _client: Node
var _native: Object
var _build_info: Dictionary = {}

var _mode := "websocket"
var _address := ""
var _endpoint := ""
var _rate_hz := 5.0
var _streaming := false
var _ws_open := false
var _http_in_flight := false
var _send_accumulator := 0.0

var _status := "offline"
var _status_detail := "telemetry disabled"
var _seq := 0
var _sent := 0
var _acknowledged := 0
var _last_rtt_ms := -1
var _pending_sent_ms: Dictionary = {}
var _event_queue: Array[Dictionary] = []

var _current_page := "Overview"
var _touch_events := 0
var _last_touch: Dictionary = {
	"count": 0,
	"kind": "none",
	"index": -1,
	"x": 0.0,
	"y": 0.0,
	"pressed": false,
}

var _location_authorization := -1
var _last_location: Dictionary = {
	"have_fix": false,
}
var _ble_state := -1
var _last_ble_device: Dictionary = {}


func _ready() -> void:
	add_to_group("ios_lab_telemetry")
	_build_info = _read_build_info()

	_client = NetworkClient.new()
	add_child(_client)
	_client.http_finished.connect(_on_http_finished)
	_client.websocket_state_changed.connect(_on_ws_state)
	_client.websocket_message.connect(_on_ws_message)
	_client.transport_error.connect(_on_transport_error)

	if OS.get_name() == "iOS" and Engine.has_singleton("IOSLab"):
		_native = Engine.get_singleton("IOSLab")
		_connect_native_signals()
	else:
		_native = null

	set_process(true)
	set_process_input(true)
	_emit_status("offline", "telemetry disabled")


func configure(mode: String, address: String, rate_hz: float) -> void:
	_mode = "http" if mode.to_lower() == "http" else "websocket"
	_address = address.strip_edges()
	_rate_hz = clampf(rate_hz, 1.0, 10.0)
	_endpoint = _normalize_endpoint(_address, _mode)


func start_stream() -> bool:
	if _endpoint.is_empty():
		_emit_status("error", "receiver address is empty")
		return false

	_sent = 0
	_acknowledged = 0
	_last_rtt_ms = -1
	_pending_sent_ms.clear()
	_event_queue.clear()
	_send_accumulator = 0.0
	_streaming = true

	if _mode == "websocket":
		_ws_open = false
		_emit_status("connecting", _endpoint)
		_client.websocket_connect(_endpoint)
	else:
		_emit_status("streaming", "HTTP POST → %s" % _endpoint)
		_queue_event("stream_started", "HTTP telemetry stream started", {"endpoint": _endpoint})
		_send_next_payload()

	return true


func stop_stream() -> void:
	if _mode == "websocket":
		_client.websocket_disconnect()
	_streaming = false
	_ws_open = false
	_http_in_flight = false
	_event_queue.clear()
	_pending_sent_ms.clear()
	_emit_status("offline", "telemetry stopped")


func is_streaming() -> bool:
	return _streaming


func get_mode() -> String:
	return _mode


func get_endpoint() -> String:
	return _endpoint


func get_rate_hz() -> float:
	return _rate_hz


func set_current_page(page_name: String) -> void:
	if page_name == _current_page:
		return
	_current_page = page_name
	record_event("page_changed", "page → %s" % page_name, {"page": page_name})


func send_probe() -> void:
	record_event(
		"manual_probe",
		"manual telemetry probe requested on iPhone",
		{
			"endpoint": _endpoint,
			"mode": _mode,
			"page": _current_page,
		}
	)
	_send_next_payload()


func record_event(kind: String, message: String, data: Dictionary = {}) -> void:
	var payload := _base_payload("event")
	payload["event"] = {
		"kind": kind,
		"message": message,
		"data": data,
	}
	_queue_payload(payload)
	_emit_log("EVENT %s · %s" % [kind, message])


func _process(delta: float) -> void:
	if not _streaming:
		return

	_cleanup_pending_acks()
	_send_accumulator += delta
	var interval := 1.0 / maxf(_rate_hz, 1.0)
	if _send_accumulator < interval:
		return

	_send_accumulator = fmod(_send_accumulator, interval)
	_send_next_payload()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_touch_events += 1
		_last_touch = {
			"count": _touch_events,
			"kind": "touch",
			"index": touch.index,
			"x": touch.position.x,
			"y": touch.position.y,
			"pressed": touch.pressed,
		}
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touch_events += 1
		_last_touch = {
			"count": _touch_events,
			"kind": "drag",
			"index": drag.index,
			"x": drag.position.x,
			"y": drag.position.y,
			"pressed": true,
			"relative_x": drag.relative.x,
			"relative_y": drag.relative.y,
		}


func _send_next_payload() -> void:
	if not _streaming:
		return

	if _mode == "websocket" and not _ws_open:
		return
	if _mode == "http" and _http_in_flight:
		return

	var payload: Dictionary
	if not _event_queue.is_empty():
		payload = _event_queue.pop_front()
	else:
		payload = _snapshot_payload()

	_send_payload(payload)


func _send_payload(payload: Dictionary) -> void:
	var seq := int(payload.get("seq", 0))
	var text := JSON.stringify(payload)
	_pending_sent_ms[seq] = Time.get_ticks_msec()
	_trim_pending_acks()

	if _mode == "websocket":
		_client.websocket_send_text(text)
		_sent += 1
	else:
		_http_in_flight = true
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
			"X-IOSLab-Schema: %s" % SCHEMA,
		])
		_client.http_request(_endpoint, "POST", headers, text)
		_sent += 1

	_emit_stats()


func _snapshot_payload() -> Dictionary:
	var payload := _base_payload("snapshot")
	payload["app"] = {
		"page": _current_page,
		"fps": Engine.get_frames_per_second(),
		"uptime_ms": Time.get_ticks_msec(),
	}
	payload["device"] = _device_snapshot()
	payload["sensors"] = {
		"accelerometer": _vector3_array(Input.get_accelerometer()),
		"gravity": _vector3_array(Input.get_gravity()),
		"gyroscope": _vector3_array(Input.get_gyroscope()),
		"magnetometer": _vector3_array(Input.get_magnetometer()),
	}
	payload["touch"] = _last_touch.duplicate(true)
	payload["location"] = _last_location.duplicate(true)
	payload["location"]["authorization"] = _location_authorization
	payload["bluetooth"] = {
		"state": _ble_state,
		"last_device": _last_ble_device.duplicate(true),
	}
	payload["capabilities"] = _capability_snapshot()
	return payload


func _base_payload(packet_type: String) -> Dictionary:
	_seq += 1
	return {
		"schema": SCHEMA,
		"type": packet_type,
		"seq": _seq,
		"sent_unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"build": _build_info.duplicate(true),
	}


func _device_snapshot() -> Dictionary:
	var screen := DisplayServer.screen_get_size()
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		addresses.append(address)

	var result := {
		"platform": OS.get_name(),
		"model": OS.get_model_name(),
		"locale": TranslationServer.get_locale(),
		"screen_px": [screen.x, screen.y],
		"local_addresses": addresses,
	}

	if _native != null and _native.has_method("get_battery_level"):
		var level := float(_native.call("get_battery_level"))
		result["battery_percent"] = int(round(level * 100.0)) if level >= 0.0 else -1
	if _native != null and _native.has_method("get_battery_state"):
		result["battery_state"] = int(_native.call("get_battery_state"))

	return result


func _capability_snapshot() -> Dictionary:
	var result := {
		"ioslab_bridge": _native != null,
	}
	if _native == null:
		return result

	if _native.has_method("is_arkit_supported"):
		result["arkit"] = bool(_native.call("is_arkit_supported"))
	if _native.has_method("is_lidar_supported"):
		result["lidar"] = bool(_native.call("is_lidar_supported"))
	if _native.has_method("is_nfc_available"):
		result["nfc"] = bool(_native.call("is_nfc_available"))
	return result


func _queue_event(kind: String, message: String, data: Dictionary = {}) -> void:
	var payload := _base_payload("event")
	payload["event"] = {
		"kind": kind,
		"message": message,
		"data": data,
	}
	_queue_payload(payload)


func _queue_payload(payload: Dictionary) -> void:
	_event_queue.append(payload)
	while _event_queue.size() > MAX_EVENT_QUEUE:
		_event_queue.pop_front()


func _connect_native_signals() -> void:
	if _native.has_signal("location_authorization_changed"):
		_native.connect("location_authorization_changed", Callable(self, "_on_native_location_authorization"))
	if _native.has_signal("location_updated"):
		_native.connect("location_updated", Callable(self, "_on_native_location"))
	if _native.has_signal("ble_state_changed"):
		_native.connect("ble_state_changed", Callable(self, "_on_native_ble_state"))
	if _native.has_signal("ble_device_found"):
		_native.connect("ble_device_found", Callable(self, "_on_native_ble_device"))


func _on_native_location_authorization(status: int) -> void:
	_location_authorization = status
	record_event("location_authorization", "CoreLocation authorization changed", {"status": status})


func _on_native_location(latitude: float, longitude: float, accuracy: float, altitude: float, speed: float) -> void:
	_last_location = {
		"have_fix": true,
		"latitude": latitude,
		"longitude": longitude,
		"accuracy_m": accuracy,
		"altitude_m": altitude,
		"speed_mps": maxf(speed, 0.0),
	}


func _on_native_ble_state(state: int) -> void:
	_ble_state = state
	record_event("ble_state", "CoreBluetooth state changed", {"state": state})


func _on_native_ble_device(name: String, uuid: String, rssi: int) -> void:
	_last_ble_device = {
		"name": name,
		"uuid": uuid,
		"rssi": rssi,
	}


func _on_ws_state(state: String) -> void:
	_ws_open = state == "open"
	if not _streaming:
		return

	match state:
		"open":
			_emit_status("streaming", "WebSocket open → %s" % _endpoint)
			_queue_event("stream_started", "WebSocket telemetry stream opened", {"endpoint": _endpoint})
			_send_next_payload()
		"connecting":
			_emit_status("connecting", _endpoint)
		"closing":
			_emit_status("closing", _endpoint)
		"closed":
			_emit_status("error", "WebSocket closed")


func _on_ws_message(text: String) -> void:
	_handle_receiver_payload(text)


func _on_http_finished(ok: bool, status_code: int, _headers: PackedStringArray, body: String) -> void:
	_http_in_flight = false
	if not _streaming:
		return

	if ok and status_code >= 200 and status_code < 300:
		_emit_status("streaming", "HTTP %d → %s" % [status_code, _endpoint])
		_handle_receiver_payload(body)
	else:
		_emit_status("error", "HTTP failed · status %d" % status_code)


func _on_transport_error(message: String) -> void:
	if _mode == "http":
		_http_in_flight = false
	_emit_status("error", message)
	_emit_log("ERROR · %s" % message)


func _handle_receiver_payload(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return

	var parsed: Variant = JSON.parse_string(trimmed)
	if parsed is Dictionary:
		var packet := parsed as Dictionary
		if str(packet.get("type", "")) == "ack":
			var ack_seq := int(packet.get("seq", -1))
			_ack_seq(ack_seq)
			return

	receiver_message.emit(trimmed)
	_emit_log("RX · %s" % trimmed.left(220))


func _ack_seq(ack_seq: int) -> void:
	if not _pending_sent_ms.has(ack_seq):
		return
	var sent_ms := int(_pending_sent_ms[ack_seq])
	_pending_sent_ms.erase(ack_seq)
	_last_rtt_ms = maxi(Time.get_ticks_msec() - sent_ms, 0)
	_acknowledged += 1
	_emit_stats()


func _cleanup_pending_acks() -> void:
	var now := Time.get_ticks_msec()
	var stale: Array = []
	for key in _pending_sent_ms.keys():
		if now - int(_pending_sent_ms[key]) > 30000:
			stale.append(key)
	for key in stale:
		_pending_sent_ms.erase(key)


func _trim_pending_acks() -> void:
	while _pending_sent_ms.size() > MAX_PENDING_ACKS:
		var keys := _pending_sent_ms.keys()
		if keys.is_empty():
			break
		_pending_sent_ms.erase(keys[0])


func _emit_status(state: String, detail: String) -> void:
	if state == _status and detail == _status_detail:
		return
	_status = state
	_status_detail = detail
	status_changed.emit(state, detail)
	_emit_log("STATE %s · %s" % [state.to_upper(), detail])


func _emit_stats() -> void:
	stats_changed.emit(_sent, _acknowledged, _last_rtt_ms)


func _emit_log(line: String) -> void:
	log_line.emit(line)


func _normalize_endpoint(address: String, mode: String) -> String:
	var value := address.strip_edges()
	if value.is_empty():
		return ""

	if mode == "http":
		if not value.begins_with("http://") and not value.begins_with("https://"):
			value = "http://" + value
	else:
		if not value.begins_with("ws://") and not value.begins_with("wss://"):
			value = "ws://" + value

	var scheme := value.find("://")
	var path_start := value.find("/", scheme + 3)
	if path_start == -1:
		value += "/telemetry"
	elif path_start == value.length() - 1:
		value += "telemetry"
	return value


func _vector3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _read_build_info() -> Dictionary:
	const PATH := "res://config/build_info.json"
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
