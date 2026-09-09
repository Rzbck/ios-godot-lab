extends Control

const SessionRecorderScript = preload("res://tracker/session_recorder.gd")
const SAMPLE_INTERVAL := 1.0 / 20.0

var _recorder: SessionRecorder
var _sample_accumulator := 0.0
var _ui_accumulator := 0.0
var _max_accel := 0.0

var _build_label: Label
var _session_label: Label
var _motion_label: Label
var _bridge_label: Label
var _recent_label: Label
var _toggle_button: Button


func _ready() -> void:
	_recorder = SessionRecorderScript.new()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_recent_session()
	_refresh_live_ui()


func _process(delta: float) -> void:
	if _recorder.is_active():
		_sample_accumulator += delta
		while _sample_accumulator >= SAMPLE_INTERVAL:
			_sample_accumulator -= SAMPLE_INTERVAL
			_capture_iphone_motion()

	_ui_accumulator += delta
	if _ui_accumulator >= 0.1:
		_ui_accumulator = 0.0
		_refresh_live_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.02, 0.025, 0.035, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 58)
	margin.add_theme_constant_override("margin_bottom", 32)
	background.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)

	var title := Label.new()
	title.text = "WATCH TRACKER"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "iPhone recorder + Apple Watch sensor companion"
	subtitle.modulate = Color(0.68, 0.72, 0.80, 1.0)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)

	_build_label = Label.new()
	_build_label.text = _build_text()
	column.add_child(_build_label)

	_add_separator(column)

	_session_label = Label.new()
	_session_label.add_theme_font_size_override("font_size", 18)
	column.add_child(_session_label)

	_toggle_button = Button.new()
	_toggle_button.text = "START SESSION"
	_toggle_button.custom_minimum_size = Vector2(0, 54)
	_toggle_button.pressed.connect(_toggle_session)
	column.add_child(_toggle_button)

	_motion_label = Label.new()
	_motion_label.add_theme_font_size_override("font_size", 15)
	column.add_child(_motion_label)

	_add_separator(column)

	_bridge_label = Label.new()
	_bridge_label.text = (
		"DATA PIPELINE\n"
		+ "iPhone motion -> recorder: READY\n"
		+ "GPS / altitude -> native bridge: NEXT\n"
		+ "Watch -> iPhone WatchConnectivity receiver: NEXT\n"
		+ "Storage: user://sessions/<session>/samples.jsonl"
	)
	_bridge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_bridge_label)

	_recent_label = Label.new()
	_recent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_recent_label)

	var note := Label.new()
	note.text = (
		"Recorder schema is already ready for location, altitude, speed, Watch motion "
		+ "and later HealthKit samples. Each sample keeps timestamp + source."
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.55, 0.60, 0.68, 1.0)
	column.add_child(note)


func _add_separator(parent: VBoxContainer) -> void:
	var separator := HSeparator.new()
	separator.modulate = Color(0.25, 0.30, 0.38, 1.0)
	parent.add_child(separator)


func _toggle_session() -> void:
	if _recorder.is_active():
		_stop_session()
	else:
		_start_session()


func _start_session() -> void:
	_max_accel = 0.0
	_sample_accumulator = 0.0

	var metadata := {
		"app_version": _build_value("version", "0.1.0-dev"),
		"git_sha": _build_value("git_sha", "UNKNOWN"),
		"target": "iphone",
		"sample_rate_hz": 20,
	}

	if not _recorder.begin(metadata):
		_session_label.text = "RECORDER ERROR\n%s" % _recorder.last_error()
		return

	_toggle_button.text = "STOP + SAVE SESSION"
	_refresh_live_ui()


func _stop_session() -> void:
	var summary := _recorder.end({"max_accel": _max_accel})
	_toggle_button.text = "START SESSION"
	_sample_accumulator = 0.0

	if summary.is_empty():
		_session_label.text = "RECORDER ERROR\n%s" % _recorder.last_error()
	else:
		_session_label.text = "SESSION SAVED\n%s" % str(summary.get("session_id", "?"))

	_refresh_recent_session()
	_refresh_live_ui()


func _capture_iphone_motion() -> void:
	var accel := Input.get_accelerometer()
	var gyro := Input.get_gyroscope()
	var gravity := Input.get_gravity()
	var magnetometer := Input.get_magnetometer()

	_max_accel = max(_max_accel, accel.length())

	_recorder.append_sample(
		"iphone",
		"motion",
		{
			"accel": _vec3(accel),
			"gyro": _vec3(gyro),
			"gravity": _vec3(gravity),
			"magnetometer": _vec3(magnetometer),
		}
	)


# Entry point reserved for the upcoming native iOS bridge.
# CLLocation / WatchConnectivity / later HealthKit samples can all land here
# without changing the on-disk recorder format.
func ingest_external_sample(
	source: String,
	kind: String,
	payload: Dictionary,
	quality: Dictionary = {}
) -> void:
	if not _recorder.is_active():
		return
	_recorder.append_sample(source, kind, payload, quality)


func _refresh_live_ui() -> void:
	var accel := Input.get_accelerometer()
	var gyro := Input.get_gyroscope()

	_motion_label.text = (
		"IPHONE MOTION\n"
		+ "accel  x %.3f   y %.3f   z %.3f\n" % [accel.x, accel.y, accel.z]
		+ "gyro   x %.3f   y %.3f   z %.3f" % [gyro.x, gyro.y, gyro.z]
	)

	if _recorder.is_active():
		_session_label.text = (
			"RECORDING\n"
			+ "session: %s\n" % _recorder.session_id()
			+ "duration: %.1f s\n" % _recorder.elapsed_seconds()
			+ "samples: %d" % _recorder.sample_count()
		)
	else:
		_session_label.text = "READY\nStart a session to record iPhone motion locally."


func _refresh_recent_session() -> void:
	var sessions := SessionRecorderScript.list_summaries(1)
	if sessions.is_empty():
		_recent_label.text = "LAST SESSION\nnone yet"
		return

	var last: Dictionary = sessions[0]
	_recent_label.text = (
		"LAST SESSION\n"
		+ "id: %s\n" % str(last.get("session_id", "?"))
		+ "duration: %.1f s\n" % float(last.get("duration_s", 0.0))
		+ "samples: %d\n" % int(last.get("sample_count", 0))
		+ "sources: %s" % JSON.stringify(last.get("samples_by_source", {}))
	)


func _vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _build_text() -> String:
	return "BUILD\nversion: %s\nsha: %s\nchannel: %s" % [
		_build_value("version", "0.1.0-dev"),
		_build_value("git_sha", "UNKNOWN"),
		_build_value("channel", "local"),
	]


func _build_value(key: String, fallback: String) -> String:
	var path := "res://config/build_info.json"
	if not FileAccess.file_exists(path):
		return fallback

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return fallback

	var info: Dictionary = parsed
	return str(info.get(key, fallback))
