extends Node

signal status_changed(state: String, detail: String)
signal stats_changed(sent: int, acknowledged: int, last_rtt_ms: int)
signal log_line(line: String)
signal receiver_message(message: String)

const NetworkClient = preload("res://scripts/services/network_client.gd")
const SCHEMA := "ioslab.telemetry.v1"
const LIVE_SCHEMA := "ioslab.live.v1"
const MAX_EVENT_QUEUE := 64
const MAX_PENDING_ACKS := 64
const OFFLINE_DIAG_PATH := "user://telemetry-offline.jsonl"
const AUTO_HTTP_AFTER_WS_FAILURES := 3

var _client: Node
var _native: Object
var _build_info: Dictionary = {}

var _requested_mode := "auto"
var _active_mode := "websocket"
var _address := ""
var _endpoint := ""
var _rate_hz := 5.0
var _streaming := false
var _ws_open := false
var _http_in_flight := false
var _send_accumulator := 0.0
var _reconnect_timer := 0.0
var _reconnect_attempt := 0

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
var _camera_inventory_signature := ""


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

	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)
	_camera_inventory_signature = JSON.stringify(_camera_snapshot().get("feeds", []))

	set_process(true)
	set_process_input(true)
	_emit_status("offline", "telemetry disabled")


func configure(mode: String, address: String, rate_hz: float) -> void:
	var clean_mode := mode.to_lower()
	_requested_mode = "http" if clean_mode == "http" else "auto"
	_address = address.strip_edges()
	_rate_hz = clampf(rate_hz, 1.0, 10.0)
	_active_mode = "http" if _requested_mode == "http" else "websocket"
	_endpoint = _normalize_endpoint(_address, _active_mode)


func start_stream() -> bool:
	if _address.is_empty():
		_emit_status("error", "receiver address is empty")
		return false

	_sent = 0
	_acknowledged = 0
	_last_rtt_ms = -1
	_pending_sent_ms.clear()
	_event_queue.clear()
	_send_accumulator = 0.0
	_reconnect_timer = 0.0
	_reconnect_attempt = 0
	_streaming = true
	_active_mode = "http" if _requested_mode == "http" else "websocket"
	_endpoint = _normalize_endpoint(_address, _active_mode)

	if _active_mode == "websocket":
		_connect_websocket()
	else:
		_emit_status("streaming", "HTTP fallback active")
		_queue_event("stream_started", "HTTP telemetry stream started", {"endpoint": _endpoint})
		_send_next_payload()

	return true


func stop_stream() -> void:
	if _active_mode == "websocket":
		_client.websocket_disconnect()
	_streaming = false
	_ws_open = false
	_http_in_flight = false
	_reconnect_timer = 0.0
	_reconnect_attempt = 0
	_event_queue.clear()
	_pending_sent_ms.clear()
	_emit_status("offline", "telemetry stopped")


func is_streaming() -> bool:
	return _streaming


func get_mode() -> String:
	return _requested_mode


func get_active_mode() -> String:
	return _active_mode


func get_endpoint() -> String:
	return _endpoint


func get_rate_hz() -> float:
	return _rate_hz


func get_live_state() -> Dictionary:
	var track_state: Dictionary = {}
	var track := get_tree().get_first_node_in_group("ios_lab_track")
	if track != null and track.has_method("get_state"):
		track_state = track.call("get_state") as Dictionary

	return {
		"schema": LIVE_SCHEMA,
		"sent_unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"build": _build_info.duplicate(true),
		"app": {
			"page": _current_page,
			"fps": Engine.get_frames_per_second(),
			"uptime_ms": Time.get_ticks_msec(),
		},
		"device": _device_snapshot(),
		"sensors": {
			"accelerometer": _vector3_array(Input.get_accelerometer()),
			"gravity": _vector3_array(Input.get_gravity()),
			"gyroscope": _vector3_array(Input.get_gyroscope()),
			"magnetometer": _vector3_array(Input.get_magnetometer()),
		},
		"touch": _last_touch.duplicate(true),
		"location": _location_snapshot(),
		"track": track_state,
		"bluetooth": {
			"state": _ble_state,
			"last_device": _last_ble_device.duplicate(true),
		},
		"camera": _camera_snapshot(),
		"capabilities": _capability_snapshot(),
		"telemetry": {
			"requested_mode": _requested_mode,
			"active_mode": _active_mode,
			"state": _status,
			"endpoint": _endpoint,
			"sent": _sent,
			"acked": _acknowledged,
			"last_rtt_ms": _last_rtt_ms,
		},
	}


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
			"mode": _active_mode,
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

	if _active_mode == "websocket" and not _ws_open and _reconnect_timer > 0.0:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_connect_websocket()

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

	if _active_mode == "websocket" and not _ws_open:
		return
	if _active_mode == "http" and _http_in_flight:
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

	if _active_mode == "websocket":
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
	var live := get_live_state()
	for key in ["app", "device", "sensors", "touch", "location", "track", "bluetooth", "camera", "capabilities", "telemetry"]:
		payload[key] = live.get(key, {})
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


func _location_snapshot() -> Dictionary:
	var result := _last_location.duplicate(true)
	result["authorization"] = _location_authorization
	return result


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


func _camera_snapshot() -> Dictionary:
	var monitoring := CameraServer.monitoring_feeds
	if not monitoring:
		return {
			"monitoring_feeds": false,
			"feed_count": 0,
			"feeds": [],
		}

	var metadata: Array = []
	for raw_feed in CameraServer.feeds():
		var feed := raw_feed as CameraFeed
		if feed == null:
			continue
		metadata.append({
			"id": feed.get_id(),
			"name": feed.get_name(),
			"position": int(feed.get_position()),
			"datatype": int(feed.get_datatype()),
			"format_count": feed.get_formats().size(),
			"active": feed.is_active(),
			"transform": str(feed.get_transform()),
		})
	return {
		"monitoring_feeds": true,
		"feed_count": metadata.size(),
		"feeds": metadata,
	}


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
	if _native.has_method("is_background_location_enabled"):
		result["background_location"] = bool(_native.call("is_background_location_enabled"))
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
		"unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
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


func _on_camera_feeds_updated() -> void:
	var snapshot := _camera_snapshot()
	var signature := JSON.stringify(snapshot.get("feeds", []))
	if signature == _camera_inventory_signature:
		return
	_camera_inventory_signature = signature
	record_event("camera_inventory", "CameraServer feed inventory changed", snapshot)


func _connect_websocket() -> void:
	if not _streaming:
		return
	_active_mode = "websocket"
	_endpoint = _normalize_endpoint(_address, "websocket")
	_ws_open = false
	_emit_status("connecting", "WebSocket connecting")
	_client.websocket_connect(_endpoint)


func _schedule_ws_reconnect(reason: String) -> void:
	if not _streaming or _active_mode != "websocket":
		return

	_reconnect_attempt += 1
	if _requested_mode == "auto" and _reconnect_attempt >= AUTO_HTTP_AFTER_WS_FAILURES:
		_activate_http_fallback(reason)
		return

	var delay := minf(pow(2.0, minf(float(_reconnect_attempt - 1), 4.0)), 15.0)
	_reconnect_timer = delay
	_emit_status("reconnecting", "WS retry in %.0f s" % delay)
	_persist_offline_diag("ws_reconnect", "%s · retry %.0f s" % [reason, delay])


func _activate_http_fallback(reason: String) -> void:
	_active_mode = "http"
	_endpoint = _normalize_endpoint(_address, "http")
	_ws_open = false
	_reconnect_timer = 0.0
	_http_in_flight = false
	_emit_status("fallback", "HTTP fallback")
	_queue_event("transport_fallback", "WebSocket unavailable; switched to HTTP", {
		"reason": reason,
		"endpoint": _endpoint,
	})
	_persist_offline_diag("http_fallback", reason)
	_send_next_payload()


func _on_ws_state(state: String) -> void:
	_ws_open = state == "open"
	if not _streaming or _active_mode != "websocket":
		return

	match state:
		"open":
			_reconnect_attempt = 0
			_reconnect_timer = 0.0
			_emit_status("streaming", "WebSocket connected")
			_queue_event("stream_started", "WebSocket telemetry stream opened", {"endpoint": _endpoint})
			_queue_offline_diagnostics()
			_send_next_payload()
		"connecting":
			_emit_status("connecting", "WebSocket connecting")
		"closing":
			_emit_status("reconnecting", "WebSocket closing")
		"closed":
			_schedule_ws_reconnect("WebSocket closed")


func _on_ws_message(text: String) -> void:
	_handle_receiver_payload(text)


func _on_http_finished(ok: bool, status_code: int, _headers: PackedStringArray, body: String) -> void:
	_http_in_flight = false
	if not _streaming or _active_mode != "http":
		return

	if ok and status_code >= 200 and status_code < 300:
		_emit_status("streaming", "HTTP connected")
		_handle_receiver_payload(body)
		_queue_offline_diagnostics()
	else:
		_emit_status("error", "HTTP %d" % status_code)
		_persist_offline_diag("http_error", "status %d" % status_code)


func _on_transport_error(message: String) -> void:
	if _active_mode == "http":
		_http_in_flight = false
		_emit_status("error", message.left(90))
		_persist_offline_diag("http_transport", message)
	else:
		_persist_offline_diag("ws_transport", message)
		if _streaming:
			_schedule_ws_reconnect(message)
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
		if value.begins_with("ws://"):
			value = "http://" + value.trim_prefix("ws://")
		elif value.begins_with("wss://"):
			value = "https://" + value.trim_prefix("wss://")
		elif not value.begins_with("http://") and not value.begins_with("https://"):
			value = "http://" + value
	else:
		if value.begins_with("http://"):
			value = "ws://" + value.trim_prefix("http://")
		elif value.begins_with("https://"):
			value = "wss://" + value.trim_prefix("https://")
		elif not value.begins_with("ws://") and not value.begins_with("wss://"):
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


func _persist_offline_diag(kind: String, message: String) -> void:
	var file: FileAccess
	if FileAccess.file_exists(OFFLINE_DIAG_PATH):
		file = FileAccess.open(OFFLINE_DIAG_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(OFFLINE_DIAG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify({
		"unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"kind": kind,
		"message": message.left(300),
		"requested_mode": _requested_mode,
		"active_mode": _active_mode,
		"endpoint": _endpoint,
	}))
	file.close()


func _queue_offline_diagnostics() -> void:
	if not FileAccess.file_exists(OFFLINE_DIAG_PATH):
		return
	var file := FileAccess.open(OFFLINE_DIAG_PATH, FileAccess.READ)
	if file == null:
		return
	var lines := file.get_as_text().split("\n", false)
	file.close()
	if lines.is_empty():
		return

	var recent: Array[String] = []
	var start := maxi(lines.size() - 20, 0)
	for index in range(start, lines.size()):
		recent.append(lines[index])

	_queue_event("offline_diagnostics", "recovered connection diagnostics", {
		"count": recent.size(),
		"records": recent,
	})
	var clear := FileAccess.open(OFFLINE_DIAG_PATH, FileAccess.WRITE)
	if clear != null:
		clear.store_string("")
		clear.close()


func _read_build_info() -> Dictionary:
	const PATH := "res://config/build_info.json"
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
