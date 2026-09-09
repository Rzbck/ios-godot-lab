extends Control

var _build_label: Label
var _watch_label: Label
var _motion_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.02, 0.025, 0.035, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 72)
	margin.add_theme_constant_override("margin_bottom", 40)
	background.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title := Label.new()
	title.text = "WATCH SENSOR LAB"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Independent iPhone / Apple Watch experiment"
	subtitle.modulate = Color(0.68, 0.72, 0.80, 1.0)
	column.add_child(subtitle)

	_build_label = Label.new()
	_build_label.text = _build_text()
	column.add_child(_build_label)

	_watch_label = Label.new()
	_watch_label.text = "WATCH LINK\nReceiver: NOT WIRED YET\nCompanion install: NOT TESTED"
	column.add_child(_watch_label)

	_motion_label = Label.new()
	_motion_label.text = "MOTION\nWaiting for WatchConnectivity bridge"
	column.add_child(_motion_label)

	var note := Label.new()
	note.text = "Bootstrap goal: prove iPhone + watchOS builds first."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.55, 0.60, 0.68, 1.0)
	column.add_child(note)


func _build_text() -> String:
	var path := "res://config/build_info.json"
	if not FileAccess.file_exists(path):
		return "BUILD\nversion: 0.1.0-dev\nsha: UNKNOWN"

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "BUILD\nversion: 0.1.0-dev\nsha: UNREADABLE"

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return "BUILD\nversion: 0.1.0-dev\nsha: INVALID"

	var info: Dictionary = parsed
	return "BUILD\nversion: %s\nsha: %s\nchannel: %s" % [
		str(info.get("version", "?")),
		str(info.get("git_sha", "?")),
		str(info.get("channel", "?")),
	]
