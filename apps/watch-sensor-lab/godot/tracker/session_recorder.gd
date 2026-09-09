class_name SessionRecorder
extends RefCounted

const ROOT_DIR := "user://sessions"
const SCHEMA_VERSION := 1

var _active := false
var _session_id := ""
var _session_dir := ""
var _samples_file: FileAccess
var _started_unix := 0.0
var _started_ticks := 0
var _sample_count := 0
var _samples_by_source: Dictionary = {}
var _metadata: Dictionary = {}
var _last_error := ""


func begin(metadata: Dictionary = {}) -> bool:
	if _active:
		_last_error = "A session is already active."
		return false

	_last_error = ""
	_started_unix = Time.get_unix_time_from_system()
	_started_ticks = Time.get_ticks_msec()
	_session_id = str(int(_started_unix * 1000.0))
	_session_dir = "%s/%s" % [ROOT_DIR, _session_id]
	_sample_count = 0
	_samples_by_source = {}
	_metadata = metadata.duplicate(true)

	var absolute_dir := ProjectSettings.globalize_path(_session_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		_last_error = "Cannot create session directory: %s" % error_string(mkdir_error)
		return false

	_samples_file = FileAccess.open(_session_dir + "/samples.jsonl", FileAccess.WRITE)
	if _samples_file == null:
		_last_error = "Cannot open samples.jsonl for writing."
		return false

	_active = true
	_store_record(
		{
			"record": "session_start",
			"schema": SCHEMA_VERSION,
			"session_id": _session_id,
			"timestamp": _started_unix,
			"metadata": _metadata,
		}
	)
	_samples_file.flush()
	return true


func append_sample(
	source: String,
	kind: String,
	payload: Dictionary,
	quality: Dictionary = {}
) -> bool:
	if not _active or _samples_file == null:
		_last_error = "No active session."
		return false

	var now := Time.get_unix_time_from_system()
	var elapsed_ms := Time.get_ticks_msec() - _started_ticks

	_store_record(
		{
			"record": "sample",
			"schema": SCHEMA_VERSION,
			"session_id": _session_id,
			"timestamp": now,
			"elapsed_ms": elapsed_ms,
			"source": source,
			"kind": kind,
			"payload": payload,
			"quality": quality,
		}
	)

	_sample_count += 1
	_samples_by_source[source] = int(_samples_by_source.get(source, 0)) + 1

	if _sample_count % 20 == 0:
		_samples_file.flush()

	return true


func end(extra_summary: Dictionary = {}) -> Dictionary:
	if not _active:
		_last_error = "No active session to stop."
		return {}

	var ended_unix := Time.get_unix_time_from_system()
	var duration_s := max(0.0, ended_unix - _started_unix)
	var summary := {
		"schema": SCHEMA_VERSION,
		"session_id": _session_id,
		"started_at": _started_unix,
		"ended_at": ended_unix,
		"duration_s": duration_s,
		"sample_count": _sample_count,
		"samples_by_source": _samples_by_source.duplicate(true),
		"metadata": _metadata.duplicate(true),
	}

	for key in extra_summary.keys():
		summary[key] = extra_summary[key]

	_store_record(
		{
			"record": "session_end",
			"schema": SCHEMA_VERSION,
			"session_id": _session_id,
			"timestamp": ended_unix,
			"summary": summary,
		}
	)

	_samples_file.flush()
	_samples_file.close()
	_samples_file = null

	var summary_file := FileAccess.open(_session_dir + "/summary.json", FileAccess.WRITE)
	if summary_file == null:
		_last_error = "Session samples saved, but summary.json could not be written."
	else:
		summary_file.store_string(JSON.stringify(summary, "\t"))
		summary_file.close()

	_active = false
	return summary


func is_active() -> bool:
	return _active


func session_id() -> String:
	return _session_id


func sample_count() -> int:
	return _sample_count


func elapsed_seconds() -> float:
	if not _active:
		return 0.0
	return float(Time.get_ticks_msec() - _started_ticks) / 1000.0


func last_error() -> String:
	return _last_error


func _store_record(record: Dictionary) -> void:
	if _samples_file != null:
		_samples_file.store_line(JSON.stringify(record))


static func list_summaries(limit: int = 20) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var directory := DirAccess.open(ROOT_DIR)
	if directory == null:
		return output

	var session_dirs: Array[String] = []
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if directory.current_is_dir() and not name.begins_with("."):
			session_dirs.append(name)
	directory.list_dir_end()

	session_dirs.sort()
	session_dirs.reverse()

	for name in session_dirs:
		var summary_path := "%s/%s/summary.json" % [ROOT_DIR, name]
		if not FileAccess.file_exists(summary_path):
			continue

		var file := FileAccess.open(summary_path, FileAccess.READ)
		if file == null:
			continue

		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			output.append(parsed)

		if output.size() >= limit:
			break

	return output
