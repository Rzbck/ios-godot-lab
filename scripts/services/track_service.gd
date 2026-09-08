extends Node

signal recording_changed(recording: bool)
signal stats_changed(state: Dictionary)
signal point_recorded(point: Dictionary)

const TRACK_DIR := "user://tracks"
const EARTH_RADIUS_M := 6371000.0
const MAX_SEGMENT_SPEED_MPS := 100.0
const ELEVATION_NOISE_M := 1.5

var _native: Object
var _recording := false
var _background_enabled := false
var _file: FileAccess
var _file_path := ""
var _summary_path := ""

var _started_unix_ms := 0
var _last_unix_ms := 0
var _points := 0
var _distance_m := 0.0
var _elevation_gain_m := 0.0
var _elevation_loss_m := 0.0
var _moving_ms := 0
var _max_speed_mps := 0.0
var _last_point: Dictionary = {}


func _ready() -> void:
	add_to_group("ios_lab_track")
	if OS.get_name() == "iOS" and Engine.has_singleton("IOSLab"):
		_native = Engine.get_singleton("IOSLab")
		if _native.has_signal("location_updated"):
			_native.connect("location_updated", Callable(self, "_on_location_updated"))
	else:
		_native = null


func start_track(background_enabled: bool = true) -> bool:
	if _recording:
		return true
	if _native == null:
		return false

	_ensure_track_dir()
	var stamp := Time.get_datetime_string_from_system(true, false).replace(":", "").replace("-", "")
	_file_path = "%s/track-%s.jsonl" % [TRACK_DIR, stamp]
	_summary_path = "%s/track-%s.summary.json" % [TRACK_DIR, stamp]
	_file = FileAccess.open(_file_path, FileAccess.WRITE)
	if _file == null:
		return false

	_started_unix_ms = _now_ms()
	_last_unix_ms = _started_unix_ms
	_points = 0
	_distance_m = 0.0
	_elevation_gain_m = 0.0
	_elevation_loss_m = 0.0
	_moving_ms = 0
	_max_speed_mps = 0.0
	_last_point = {}
	_background_enabled = background_enabled
	_recording = true

	if _native.has_method("set_background_location_enabled"):
		_native.call("set_background_location_enabled", _background_enabled)
	if _native.has_method("request_location"):
		_native.call("request_location")
	if _native.has_method("start_location"):
		_native.call("start_location")

	_write_jsonl({
		"schema": "ioslab.track.v1",
		"type": "start",
		"started_unix_ms": _started_unix_ms,
		"background": _background_enabled,
	})
	_write_summary()
	recording_changed.emit(true)
	stats_changed.emit(get_state())
	return true


func stop_track() -> Dictionary:
	if not _recording:
		return get_state()

	_recording = false
	if _native != null and _native.has_method("set_background_location_enabled"):
		_native.call("set_background_location_enabled", false)
	_background_enabled = false

	_write_jsonl({
		"schema": "ioslab.track.v1",
		"type": "stop",
		"stopped_unix_ms": _now_ms(),
		"summary": get_state(),
	})
	_write_summary()
	if _file != null:
		_file.flush()
		_file.close()
	_file = null

	recording_changed.emit(false)
	stats_changed.emit(get_state())
	return get_state()


func is_recording() -> bool:
	return _recording


func get_state() -> Dictionary:
	var now := _now_ms()
	var duration_ms := maxi((now if _recording else _last_unix_ms) - _started_unix_ms, 0) if _started_unix_ms > 0 else 0
	var moving_s := float(_moving_ms) / 1000.0
	var avg_speed := _distance_m / moving_s if moving_s > 0.0 else 0.0
	return {
		"recording": _recording,
		"background": _background_enabled,
		"points": _points,
		"distance_m": _distance_m,
		"elevation_gain_m": _elevation_gain_m,
		"elevation_loss_m": _elevation_loss_m,
		"duration_s": float(duration_ms) / 1000.0,
		"moving_s": moving_s,
		"average_speed_mps": avg_speed,
		"max_speed_mps": _max_speed_mps,
		"file": _file_path,
		"summary_file": _summary_path,
		"last_point": _last_point.duplicate(true),
	}


func _on_location_updated(latitude: float, longitude: float, accuracy: float, altitude: float, speed: float) -> void:
	if not _recording:
		return

	var now := _now_ms()
	var point := {
		"schema": "ioslab.track.v1",
		"type": "point",
		"unix_ms": now,
		"latitude": latitude,
		"longitude": longitude,
		"accuracy_m": accuracy,
		"altitude_m": altitude,
		"speed_mps": maxf(speed, 0.0),
	}

	if not _last_point.is_empty():
		var dt_s := maxf(float(now - int(_last_point.get("unix_ms", now))) / 1000.0, 0.001)
		var segment_m := _haversine_m(
			float(_last_point.get("latitude", latitude)),
			float(_last_point.get("longitude", longitude)),
			latitude,
			longitude
		)
		var implied_speed := segment_m / dt_s
		var valid_segment := (
			accuracy >= 0.0
			and accuracy <= 100.0
			and float(_last_point.get("accuracy_m", 9999.0)) <= 100.0
			and implied_speed <= MAX_SEGMENT_SPEED_MPS
		)
		if valid_segment:
			_distance_m += segment_m
			point["segment_m"] = segment_m
			var previous_alt := float(_last_point.get("altitude_m", altitude))
			var altitude_delta := altitude - previous_alt
			if absf(altitude_delta) >= ELEVATION_NOISE_M:
				if altitude_delta > 0.0:
					_elevation_gain_m += altitude_delta
				else:
					_elevation_loss_m += -altitude_delta

		var movement_speed := maxf(float(point["speed_mps"]), implied_speed if valid_segment else 0.0)
		if movement_speed > 0.5:
			_moving_ms += now - int(_last_point.get("unix_ms", now))

	_last_point = point.duplicate(true)
	_last_unix_ms = now
	_points += 1
	_max_speed_mps = maxf(_max_speed_mps, float(point["speed_mps"]))

	_write_jsonl(point)
	_write_summary()
	point_recorded.emit(point)
	stats_changed.emit(get_state())


func _write_jsonl(record: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(record))
	_file.flush()


func _write_summary() -> void:
	if _summary_path.is_empty():
		return
	var summary := FileAccess.open(_summary_path, FileAccess.WRITE)
	if summary != null:
		summary.store_string(JSON.stringify(get_state(), "\t"))
		summary.close()


func _ensure_track_dir() -> void:
	var absolute := ProjectSettings.globalize_path(TRACK_DIR)
	DirAccess.make_dir_recursive_absolute(absolute)


func _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - lat1)
	var dl := deg_to_rad(lon2 - lon1)
	var a := sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	var c := 2.0 * atan2(sqrt(a), sqrt(maxf(1.0 - a, 0.0)))
	return EARTH_RADIUS_M * c


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
