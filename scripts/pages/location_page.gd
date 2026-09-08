extends VBoxContainer

const UI = preload("res://scripts/ui.gd")
const LocationService = preload("res://scripts/services/location_service.gd")
const SlippyMap = preload("res://scripts/widgets/slippy_map.gd")

var _service: Node
var _map: VBoxContainer

var _bridge_status: Label
var _auth_status: Label
var _latitude: Label
var _longitude: Label
var _accuracy: Label
var _altitude: Label
var _speed: Label

var _ble_state: Label
var _ble_devices: Label
var _ble_seen: Dictionary = {}

var _arkit: Label
var _lidar: Label
var _nfc: Label

var _last_latitude := 0.0
var _last_longitude := 0.0
var _have_location := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Location",
		"GPS, map, Bluetooth LE and Apple hardware capability probes."
	)

	_service = LocationService.new()
	_service.availability_changed.connect(_on_availability_changed)
	_service.authorization_changed.connect(_on_authorization_changed)
	_service.location_updated.connect(_on_location_updated)
	_service.ble_state_changed.connect(_on_ble_state_changed)
	_service.ble_device_found.connect(_on_ble_device_found)

	var location_card := UI.make_card(
		self,
		"GPS",
		"Permission is requested only when you press Start. Location stays local unless you explicitly enable Telemetry."
	)
	_bridge_status = UI.value_row(location_card, "Bridge", "detecting…")
	_auth_status = UI.value_row(location_card, "Permission", "unknown")
	_latitude = UI.value_row(location_card, "Latitude", "—")
	_longitude = UI.value_row(location_card, "Longitude", "—")
	_accuracy = UI.value_row(location_card, "Accuracy", "—")
	_altitude = UI.value_row(location_card, "Altitude", "—")
	_speed = UI.value_row(location_card, "Speed", "—")

	var location_buttons := HBoxContainer.new()
	location_buttons.add_theme_constant_override("separation", 8)
	location_card.add_child(location_buttons)

	var start := UI.button("Start Location", true)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_request_and_start_location)
	location_buttons.add_child(start)

	var stop := UI.button("Stop")
	stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop.pressed.connect(_stop_location)
	location_buttons.add_child(stop)

	var maps := UI.button("Open in Apple Maps")
	maps.pressed.connect(_open_apple_maps)
	location_card.add_child(maps)

	var map_card := UI.make_card(self, "MAP", "Live OpenStreetMap position with recentering and zoom.")
	_map = SlippyMap.new()
	map_card.add_child(_map)

	var ble := UI.make_card(self, "BLUETOOTH LE", "Scans nearby advertisements without pairing.")
	_ble_state = UI.value_row(ble, "State", "not started")
	_ble_devices = UI.value_row(ble, "Nearby", "none")

	var ble_buttons := HBoxContainer.new()
	ble_buttons.add_theme_constant_override("separation", 8)
	ble.add_child(ble_buttons)

	var scan := UI.button("Start Scan", true)
	scan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan.pressed.connect(_start_ble)
	ble_buttons.add_child(scan)

	var stop_scan := UI.button("Stop")
	stop_scan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_scan.pressed.connect(_stop_ble)
	ble_buttons.add_child(stop_scan)

	var apple := UI.make_card(self, "APPLE CAPABILITIES")
	_arkit = UI.value_row(apple, "ARKit", "checking…")
	_lidar = UI.value_row(apple, "LiDAR", "checking…")
	_nfc = UI.value_row(apple, "NFC", "checking…")

	add_child(_service)
	call_deferred("_refresh_capability_probes")


func _request_and_start_location() -> void:
	if not _service.is_available():
		_bridge_status.text = "bridge unavailable"
		return
	_service.request_location()
	_service.start_location()


func _stop_location() -> void:
	_service.stop_location()


func _start_ble() -> void:
	_ble_seen.clear()
	_ble_devices.text = "scanning…"
	_service.start_ble_scan()


func _stop_ble() -> void:
	_service.stop_ble_scan()


func _open_apple_maps() -> void:
	if not _have_location:
		_auth_status.text = "need GPS fix"
		return
	var url := "https://maps.apple.com/?ll=%.7f,%.7f&q=Current%%20Location" % [_last_latitude, _last_longitude]
	OS.shell_open(url)


func _on_availability_changed(available: bool) -> void:
	_bridge_status.text = "ready" if available else "unavailable"


func _on_authorization_changed(status: int) -> void:
	_auth_status.text = _authorization_name(status)


func _on_location_updated(latitude: float, longitude: float, accuracy: float, altitude: float, speed: float) -> void:
	_last_latitude = latitude
	_last_longitude = longitude
	_have_location = true

	_latitude.text = "%.6f°" % latitude
	_longitude.text = "%.6f°" % longitude
	_accuracy.text = "± %.1f m" % accuracy
	_altitude.text = "%.1f m" % altitude
	_speed.text = "%.2f m/s" % maxf(speed, 0.0)
	_map.set_location(latitude, longitude)


func _on_ble_state_changed(state: int) -> void:
	_ble_state.text = _ble_state_name(state)


func _on_ble_device_found(name: String, uuid: String, rssi: int) -> void:
	_ble_seen[uuid] = {
		"name": name if not name.is_empty() else "unnamed",
		"rssi": rssi,
	}
	var label := name if not name.is_empty() else "unnamed"
	_ble_devices.text = "%d seen · %s · %d dBm" % [_ble_seen.size(), label, rssi]


func _refresh_capability_probes() -> void:
	if not _service.is_available():
		_arkit.text = "bridge unavailable"
		_lidar.text = "bridge unavailable"
		_nfc.text = "bridge unavailable"
		return

	_arkit.text = "supported" if _service.is_arkit_supported() else "not supported"
	_lidar.text = "supported" if _service.is_lidar_supported() else "not supported"
	_nfc.text = "available" if _service.is_nfc_available() else "not available"


func _authorization_name(status: int) -> String:
	match status:
		0:
			return "not determined"
		1:
			return "restricted"
		2:
			return "denied"
		3:
			return "always"
		4:
			return "while using"
		_:
			return "status %d" % status


func _ble_state_name(state: int) -> String:
	match state:
		0:
			return "unknown"
		1:
			return "resetting"
		2:
			return "unsupported"
		3:
			return "unauthorized"
		4:
			return "off"
		5:
			return "on"
		_:
			return "state %d" % state
