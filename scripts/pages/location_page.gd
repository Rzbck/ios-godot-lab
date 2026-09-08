extends VBoxContainer

const UI = preload("res://scripts/ui.gd")
const LocationService = preload("res://scripts/services/location_service.gd")
const SlippyMap = preload("res://scripts/widgets/slippy_map.gd")

var _service: Node
var _track: Node
var _map: VBoxContainer

var _bridge_status: Label
var _auth_status: Label
var _latitude: Label
var _longitude: Label
var _accuracy: Label
var _altitude: Label
var _speed: Label

var _track_state: Label
var _track_points: Label
var _track_distance: Label
var _track_elevation: Label
var _track_duration: Label
var _track_speed: Label

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
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"Location",
		"Live GPS, map, background track recording and Apple hardware probes."
	)

	_service = LocationService.new()
	_service.availability_changed.connect(_on_availability_changed)
	_service.authorization_changed.connect(_on_authorization_changed)
	_service.location_updated.connect(_on_location_updated)
	_service.ble_state_changed.connect(_on_ble_state_changed)
	_service.ble_device_found.connect(_on_ble_device_found)

	_build_location_card()
	_build_track_card()
	_build_map_card()
	_build_ble_card()
	_build_capability_card()

	add_child(_service)
	_track = get_tree().get_first_node_in_group("ios_lab_track")
	if _track != null:
		_track.recording_changed.connect(_on_track_recording_changed)
		_track.stats_changed.connect(_on_track_stats_changed)
		_refresh_track_state(_track.get_state())
	call_deferred("_refresh_capability_probes")


func _build_location_card() -> void:
	var card := UI.make_card(
		self,
		"GPS",
		"Request location only when needed. Live telemetry and Live Output can route this data to your computer."
	)
	_bridge_status = UI.value_row(card, "Bridge", "detecting…")
	_auth_status = UI.value_row(card, "Permission", "unknown")
	_latitude = UI.value_row(card, "Latitude", "—")
	_longitude = UI.value_row(card, "Longitude", "—")
	_accuracy = UI.value_row(card, "Accuracy", "—")
	_altitude = UI.value_row(card, "Altitude", "—")
	_speed = UI.value_row(card, "Speed", "—")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var start := UI.button("START GPS", true)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_request_and_start_location)
	row.add_child(start)

	var stop := UI.button("STOP")
	stop.custom_minimum_size.x = 92
	stop.pressed.connect(_stop_location)
	row.add_child(stop)


func _build_track_card() -> void:
	var card := UI.make_card(
		self,
		"TRACK RECORDER",
		"Records a local JSONL route and derived metrics. Background mode keeps CoreLocation active after you lock the phone or leave the app, subject to iOS permissions and system policy."
	)
	_track_state = UI.value_row(card, "State", "stopped")
	_track_points = UI.value_row(card, "Points", "0")
	_track_distance = UI.value_row(card, "Distance", "0 m")
	_track_elevation = UI.value_row(card, "Elevation", "+0 / -0 m")
	_track_duration = UI.value_row(card, "Duration", "0:00")
	_track_speed = UI.value_row(card, "Speed", "avg 0 · max 0 km/h")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var start_track := UI.button("START TRACK", true)
	start_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_track.pressed.connect(_start_track)
	row.add_child(start_track)

	var stop_track := UI.button("STOP & SAVE")
	stop_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_track.pressed.connect(_stop_track)
	row.add_child(stop_track)


func _build_map_card() -> void:
	var card := UI.make_card(
		self,
		"MAP",
		"OpenStreetMap position preview. The local track file keeps raw points for later traces and analysis."
	)
	_map = SlippyMap.new()
	card.add_child(_map)

	var maps := UI.button("OPEN IN APPLE MAPS")
	maps.pressed.connect(_open_apple_maps)
	card.add_child(maps)


func _build_ble_card() -> void:
	var ble := UI.make_card(
		self,
		"BLUETOOTH LE",
		"Scans nearby BLE advertisements. No pairing is performed."
	)
	_ble_state = UI.value_row(ble, "State", "not started")
	_ble_devices = UI.value_row(ble, "Last device", "none")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ble.add_child(row)

	var scan := UI.button("START SCAN", true)
	scan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan.pressed.connect(_start_ble)
	row.add_child(scan)

	var stop_scan := UI.button("STOP")
	stop_scan.custom_minimum_size.x = 92
	stop_scan.pressed.connect(_stop_ble)
	row.add_child(stop_scan)


func _build_capability_card() -> void:
	var apple := UI.make_card(self, "APPLE CAPABILITIES")
	_arkit = UI.value_row(apple, "ARKit", "checking…")
	_lidar = UI.value_row(apple, "LiDAR", "checking…")
	_nfc = UI.value_row(apple, "NFC", "checking…")


func _request_and_start_location() -> void:
	if not _service.is_available():
		_bridge_status.text = "bridge unavailable"
		return
	_service.request_location()
	_service.start_location()


func _stop_location() -> void:
	_service.stop_location()


func _start_track() -> void:
	if _track == null:
		_track_state.text = "track service unavailable"
		return
	if _track.start_track(true):
		_track_state.text = "RECORDING · BACKGROUND"
	else:
		_track_state.text = "could not start"


func _stop_track() -> void:
	if _track == null:
		return
	var state := _track.stop_track()
	_refresh_track_state(state)


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
	var url := "https://maps.apple.com/?ll=%.7f,%.7f&q=Current%%20Location" % [
		_last_latitude,
		_last_longitude
	]
	OS.shell_open(url)


func _on_availability_changed(available: bool) -> void:
	_bridge_status.text = "ready" if available else "unavailable"


func _on_authorization_changed(status: int) -> void:
	_auth_status.text = _authorization_name(status)


func _on_location_updated(latitude: float, longitude: float, accuracy: float, altitude: float, speed: float) -> void:
	_last_latitude = latitude
	_last_longitude = longitude
	_have_location = true

	_latitude.text = "%.7f°" % latitude
	_longitude.text = "%.7f°" % longitude
	_accuracy.text = "± %.1f m" % accuracy
	_altitude.text = "%.1f m" % altitude
	_speed.text = "%.1f km/h" % (maxf(speed, 0.0) * 3.6)
	_map.set_location(latitude, longitude)


func _on_track_recording_changed(recording: bool) -> void:
	_track_state.text = "RECORDING · BACKGROUND" if recording else "saved"


func _on_track_stats_changed(state: Dictionary) -> void:
	_refresh_track_state(state)


func _refresh_track_state(state: Dictionary) -> void:
	if _track_state == null:
		return
	var recording := bool(state.get("recording", false))
	_track_state.text = "RECORDING · BACKGROUND" if recording else "stopped / saved"
	_track_points.text = str(int(state.get("points", 0)))
	_track_distance.text = _format_distance(float(state.get("distance_m", 0.0)))
	_track_elevation.text = "+%.0f / -%.0f m" % [
		float(state.get("elevation_gain_m", 0.0)),
		float(state.get("elevation_loss_m", 0.0)),
	]
	_track_duration.text = _format_duration(float(state.get("duration_s", 0.0)))
	_track_speed.text = "avg %.1f · max %.1f km/h" % [
		float(state.get("average_speed_mps", 0.0)) * 3.6,
		float(state.get("max_speed_mps", 0.0)) * 3.6,
	]


func _on_ble_state_changed(state: int) -> void:
	_ble_state.text = _ble_state_name(state)


func _on_ble_device_found(name: String, uuid: String, rssi: int) -> void:
	_ble_seen[uuid] = {
		"name": name if not name.is_empty() else "unnamed",
		"rssi": rssi,
	}
	_ble_devices.text = "%s · %d dBm" % [
		name if not name.is_empty() else "unnamed",
		rssi,
	]


func _refresh_capability_probes() -> void:
	if not _service.is_available():
		_arkit.text = "unavailable"
		_lidar.text = "unavailable"
		_nfc.text = "unavailable"
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
			return "when in use"
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
			return "powered off"
		5:
			return "powered on"
		_:
			return "state %d" % state


func _format_distance(meters: float) -> String:
	return "%.2f km" % (meters / 1000.0) if meters >= 1000.0 else "%.0f m" % meters


func _format_duration(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var secs := total % 60
	return "%d:%02d:%02d" % [hours, minutes, secs] if hours > 0 else "%d:%02d" % [minutes, secs]
