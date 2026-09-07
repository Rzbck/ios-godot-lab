extends Node

signal availability_changed(available: bool)
signal authorization_changed(status: int)
signal location_updated(latitude: float, longitude: float, accuracy: float, altitude: float, speed: float)
signal ble_state_changed(state: int)
signal ble_device_found(name: String, uuid: String, rssi: int)

var _native: Object


func _ready() -> void:
	if OS.get_name() == "iOS" and Engine.has_singleton("IOSLab"):
		_native = Engine.get_singleton("IOSLab")
		_connect_native_signals()
		availability_changed.emit(true)
	else:
		_native = null
		availability_changed.emit(false)


func is_available() -> bool:
	return _native != null


func request_location() -> void:
	if _has_method("request_location"):
		_native.call("request_location")


func start_location() -> void:
	if _has_method("start_location"):
		_native.call("start_location")


func stop_location() -> void:
	if _has_method("stop_location"):
		_native.call("stop_location")


func start_ble_scan() -> void:
	if _has_method("start_ble_scan"):
		_native.call("start_ble_scan")


func stop_ble_scan() -> void:
	if _has_method("stop_ble_scan"):
		_native.call("stop_ble_scan")


func get_ble_state() -> int:
	if _has_method("get_ble_state"):
		return int(_native.call("get_ble_state"))
	return -1


func is_arkit_supported() -> bool:
	if _has_method("is_arkit_supported"):
		return bool(_native.call("is_arkit_supported"))
	return false


func is_lidar_supported() -> bool:
	if _has_method("is_lidar_supported"):
		return bool(_native.call("is_lidar_supported"))
	return false


func is_nfc_available() -> bool:
	if _has_method("is_nfc_available"):
		return bool(_native.call("is_nfc_available"))
	return false


func _has_method(method_name: StringName) -> bool:
	return _native != null and _native.has_method(method_name)


func _connect_native_signals() -> void:
	if _native.has_signal("location_authorization_changed"):
		_native.connect("location_authorization_changed", _on_authorization_changed)
	if _native.has_signal("location_updated"):
		_native.connect("location_updated", _on_location_updated)
	if _native.has_signal("ble_state_changed"):
		_native.connect("ble_state_changed", _on_ble_state_changed)
	if _native.has_signal("ble_device_found"):
		_native.connect("ble_device_found", _on_ble_device_found)


func _on_authorization_changed(status: int) -> void:
	authorization_changed.emit(status)


func _on_location_updated(latitude: float, longitude: float, accuracy: float, altitude: float, speed: float) -> void:
	location_updated.emit(latitude, longitude, accuracy, altitude, speed)


func _on_ble_state_changed(state: int) -> void:
	ble_state_changed.emit(state)


func _on_ble_device_found(name: String, uuid: String, rssi: int) -> void:
	ble_device_found.emit(name, uuid, rssi)
