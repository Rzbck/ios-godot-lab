extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

const CAMERA_SHADER := """
shader_type canvas_item;

uniform sampler2D cbcr_tex;
uniform int color_mode = 0;
uniform int rotation_quarters = 0;
uniform bool mirror_x = false;
uniform bool flip_y = false;

vec2 camera_uv(vec2 uv) {
	if (rotation_quarters == 1) {
		uv = vec2(uv.y, 1.0 - uv.x);
	} else if (rotation_quarters == 2) {
		uv = vec2(1.0 - uv.x, 1.0 - uv.y);
	} else if (rotation_quarters == 3) {
		uv = vec2(1.0 - uv.y, uv.x);
	}
	if (mirror_x) {
		uv.x = 1.0 - uv.x;
	}
	if (flip_y) {
		uv.y = 1.0 - uv.y;
	}
	return uv;
}

void fragment() {
	vec2 uv = camera_uv(UV);
	if (color_mode == 1) {
		float y = texture(TEXTURE, uv).r;
		vec2 cbcr = texture(cbcr_tex, uv).rg - vec2(0.5, 0.5);
		float r = y + 1.402 * cbcr.y;
		float g = y - 0.344136 * cbcr.x - 0.714136 * cbcr.y;
		float b = y + 1.772 * cbcr.x;
		COLOR = vec4(clamp(vec3(r, g, b), vec3(0.0), vec3(1.0)), 1.0);
	} else {
		COLOR = texture(TEXTURE, uv);
	}
}
"""

const CAMERA_DISCOVERY_TIMEOUT_S := 5.0
const CAMERA_DISCOVERY_POLL_S := 0.20

var _camera_status: Label
var _camera_preview: TextureRect
var _camera_selector: OptionButton
var _camera_rotation: OptionButton
var _camera_mirror: OptionButton
var _camera_texture: CameraTexture
var _camera_cbcr_texture: CameraTexture
var _camera_material: ShaderMaterial
var _camera_feeds: Array[CameraFeed] = []
var _active_feed: CameraFeed
var _camera_requested_feed_id := -1
var _camera_inventory_signature := ""
var _camera_start_token := 0
var _rebuilding_camera_selector := false

var _mic_status: Label
var _mic_level: Label
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _mic_bus_index := -1

var _power: Label
var _locale: Label
var _clipboard_status: Label
var _haptic_status: Label
var _ioslab: Object
var _system_refresh_accumulator := 0.0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = 0
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if OS.get_name() == "iOS" and Engine.has_singleton("IOSLab"):
		_ioslab = Engine.get_singleton("IOSLab")
	else:
		_ioslab = null

	UI.section_title(
		self,
		"Device",
		"Camera, microphone, battery, clipboard and haptics. Camera discovery is monitored and reported to telemetry."
	)

	_build_camera_card()
	_build_microphone_card()
	_build_system_card()

	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)
	visibility_changed.connect(_on_visibility_changed)

	set_process(true)
	_refresh_system_info()
	_refresh_camera_feeds(-1, true)


func _build_camera_card() -> void:
	var card := UI.make_card(
		self,
		"CAMERA",
		"START CAMERA waits for iOS feed discovery instead of assuming feeds exist after a fixed delay. Choose front/rear, then adjust orientation or mirror if needed."
	)
	_camera_status = UI.value_row(card, "Status", "not started")

	_camera_selector = UI.option_button(["Detect cameras…"])
	_camera_selector.item_selected.connect(_on_camera_selector_changed)
	card.add_child(_camera_selector)

	_camera_rotation = UI.option_button([
		"Orientation · Auto",
		"Rotation · 0°",
		"Rotation · 90°",
		"Rotation · 180°",
		"Rotation · 270°",
	])
	_camera_rotation.item_selected.connect(_on_camera_view_changed)
	card.add_child(_camera_rotation)

	_camera_mirror = UI.option_button([
		"Mirror · Auto",
		"Mirror · Off",
		"Mirror · On",
	])
	_camera_mirror.item_selected.connect(_on_camera_view_changed)
	card.add_child(_camera_mirror)

	_camera_preview = TextureRect.new()
	_camera_preview.custom_minimum_size = Vector2(0, 280)
	_camera_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camera_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_camera_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_camera_preview)

	var shader := Shader.new()
	shader.code = CAMERA_SHADER
	_camera_material = ShaderMaterial.new()
	_camera_material.shader = shader
	_camera_preview.material = _camera_material

	var start := UI.button("START CAMERA", true)
	start.pressed.connect(_start_camera)
	card.add_child(start)

	var stop := UI.button("STOP CAMERA")
	stop.pressed.connect(_stop_camera)
	card.add_child(stop)


func _build_microphone_card() -> void:
	var card := UI.make_card(
		self,
		"MICROPHONE",
		"Muted RMS meter only. Audio is neither saved nor transmitted."
	)
	_mic_status = UI.value_row(card, "Status", "not started")
	_mic_level = UI.value_row(card, "Level", "—")

	var start := UI.button("START MIC", true)
	start.pressed.connect(_start_microphone)
	card.add_child(start)

	var stop := UI.button("STOP MIC")
	stop.pressed.connect(_stop_microphone)
	card.add_child(stop)


func _build_system_card() -> void:
	var card := UI.make_card(self, "SYSTEM")
	_power = UI.value_row(card, "Battery", "reading…")
	_locale = UI.value_row(card, "Locale", "reading…")
	UI.value_row(card, "Model", OS.get_model_name())
	UI.value_row(card, "OS", OS.get_name())

	var actions := UI.make_card(
		self,
		"DEVICE ACTIONS",
		"Small integration probes."
	)
	_clipboard_status = UI.value_row(actions, "Clipboard", "not tested")
	_haptic_status = UI.value_row(actions, "Haptic", "not tested")

	var copy := UI.button("COPY TEST TEXT")
	copy.pressed.connect(_copy_test_text)
	actions.add_child(copy)

	var read := UI.button("READ CLIPBOARD")
	read.pressed.connect(_read_clipboard)
	actions.add_child(read)

	var haptic := UI.button("VIBRATE 150 ms", true)
	haptic.pressed.connect(_vibrate)
	actions.add_child(haptic)

	var settings := UI.button("OPEN IOS SETTINGS")
	settings.pressed.connect(_open_settings)
	actions.add_child(settings)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	_system_refresh_accumulator += delta
	if _system_refresh_accumulator >= 5.0:
		_system_refresh_accumulator = 0.0
		_refresh_system_info()

	if _capture != null:
		var available := _capture.get_frames_available()
		if available > 0:
			var frames := mini(available, 1024)
			var buffer := _capture.get_buffer(frames)
			var sum := 0.0
			for sample in buffer:
				sum += (sample.x * sample.x + sample.y * sample.y) * 0.5
			if buffer.size() > 0:
				var rms := sqrt(sum / float(buffer.size()))
				var db := linear_to_db(maxf(rms, 0.000001))
				_mic_level.text = "%.1f dBFS" % db


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_telemetry_event("camera_page_visible", "Device camera page opened", _camera_debug_snapshot())
	else:
		if _camera_texture != null or _active_feed != null:
			_stop_camera(true)


func _start_camera() -> void:
	_camera_start_token += 1
	var token := _camera_start_token
	var preferred_id := _camera_requested_feed_id
	if preferred_id < 0:
		preferred_id = _selected_camera_feed_id()

	_deactivate_camera_textures()
	CameraServer.monitoring_feeds = true
	_camera_status.text = "discovering cameras…"
	_telemetry_event("camera_start", "camera discovery requested", _camera_debug_snapshot())

	var deadline_ms := Time.get_ticks_msec() + int(CAMERA_DISCOVERY_TIMEOUT_S * 1000.0)
	while token == _camera_start_token and CameraServer.get_feed_count() == 0 and Time.get_ticks_msec() < deadline_ms:
		await get_tree().create_timer(CAMERA_DISCOVERY_POLL_S).timeout

	if token != _camera_start_token:
		return

	_refresh_camera_feeds(preferred_id, true)
	if _camera_feeds.is_empty():
		_camera_status.text = "no feed after 5 s · tap START to retry"
		_telemetry_event("camera_error", "camera discovery timed out with zero Godot feeds", _camera_debug_snapshot())
		return

	var selected := clampi(_camera_selector.selected, 0, _camera_feeds.size() - 1)
	var feed := _camera_feeds[selected]
	if feed == null:
		_camera_status.text = "invalid camera feed"
		_telemetry_event("camera_error", "selected camera feed is invalid", _camera_debug_snapshot())
		return

	_active_feed = feed
	_camera_requested_feed_id = feed.get_id()
	var datatype := int(feed.get_datatype())
	var formats := feed.get_formats()
	var format_probe := false

	if datatype == 2 and not formats.is_empty():
		format_probe = feed.set_format(0, {})
		datatype = int(feed.get_datatype())

	_camera_texture = CameraTexture.new()
	_camera_texture.camera_feed_id = feed.get_id()

	var color_mode := "rgba/direct"
	if datatype == 3:
		_camera_texture.which_feed = CameraServer.FEED_Y_IMAGE
		_camera_cbcr_texture = CameraTexture.new()
		_camera_cbcr_texture.camera_feed_id = feed.get_id()
		_camera_cbcr_texture.which_feed = CameraServer.FEED_CBCR_IMAGE
		_camera_cbcr_texture.camera_is_active = true
		_camera_material.set_shader_parameter("cbcr_tex", _camera_cbcr_texture)
		_camera_material.set_shader_parameter("color_mode", 1)
		color_mode = "ycbcr-separate→rgb"
	else:
		_camera_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
		_camera_material.set_shader_parameter("color_mode", 0)

	_camera_texture.camera_is_active = true
	_camera_preview.texture = _camera_texture
	_apply_camera_preview_transform()

	var position_name := _feed_position_name(feed.get_position())
	_camera_status.text = "%s · %s" % [position_name, color_mode]
	var active_data := _camera_debug_snapshot()
	active_data["feed_id"] = feed.get_id()
	active_data["feed"] = feed.get_name()
	active_data["position"] = position_name
	active_data["datatype"] = datatype
	active_data["datatype_name"] = _datatype_name(datatype)
	active_data["format_count"] = formats.size()
	active_data["format_probe_ok"] = format_probe
	active_data["color_mode"] = color_mode
	active_data["rotation"] = _rotation_degrees()
	active_data["mirror"] = _mirror_enabled()
	active_data["feed_transform"] = str(feed.get_transform())
	active_data["preview_size"] = [_camera_preview.size.x, _camera_preview.size.y]
	_telemetry_event("camera_active", "camera feed active", active_data)


func _refresh_camera_feeds(preferred_id: int = -1, force_ui: bool = false) -> void:
	var feeds := CameraServer.feeds()
	var fresh_feeds: Array[CameraFeed] = []
	var metadata: Array = []

	for raw_feed in feeds:
		var feed := raw_feed as CameraFeed
		if feed == null:
			continue
		fresh_feeds.append(feed)
		metadata.append({
			"id": feed.get_id(),
			"name": feed.get_name(),
			"position": _feed_position_name(feed.get_position()),
			"datatype": int(feed.get_datatype()),
			"datatype_name": _datatype_name(int(feed.get_datatype())),
			"format_count": feed.get_formats().size(),
			"active": feed.is_active(),
		})

	var signature := JSON.stringify(metadata)
	if not force_ui and signature == _camera_inventory_signature:
		return
	_camera_inventory_signature = signature
	_camera_feeds = fresh_feeds

	if preferred_id < 0:
		preferred_id = _camera_requested_feed_id

	_rebuilding_camera_selector = true
	_camera_selector.clear()
	var preferred_index := -1
	var rear_index := -1

	for index in range(_camera_feeds.size()):
		var feed := _camera_feeds[index]
		var position := _feed_position_name(feed.get_position())
		_camera_selector.add_item("%s · %s" % [position, feed.get_name()])
		if feed.get_id() == preferred_id:
			preferred_index = index
		if rear_index < 0 and int(feed.get_position()) == 2:
			rear_index = index

	if _camera_feeds.is_empty():
		_camera_selector.add_item("No camera feeds")
		_camera_selector.disabled = true
	else:
		_camera_selector.disabled = false
		if preferred_index < 0:
			preferred_index = rear_index if rear_index >= 0 else 0
		_camera_selector.select(preferred_index)
		_camera_requested_feed_id = _camera_feeds[preferred_index].get_id()
	_rebuilding_camera_selector = false

	var event_data := _camera_debug_snapshot()
	event_data["feeds"] = metadata
	_telemetry_event("camera_feeds", "camera feed inventory changed", event_data)

	if _active_feed == null and not _camera_feeds.is_empty() and CameraServer.monitoring_feeds:
		_camera_status.text = "%d camera(s) detected · tap START" % _camera_feeds.size()


func _on_camera_feeds_updated() -> void:
	if not CameraServer.monitoring_feeds and _active_feed == null:
		return
	_refresh_camera_feeds(_camera_requested_feed_id, false)


func _stop_camera(emit_event: bool = true) -> void:
	_camera_start_token += 1
	_deactivate_camera_textures()
	CameraServer.monitoring_feeds = false
	if _camera_status != null:
		_camera_status.text = "stopped"
	if emit_event:
		_telemetry_event("camera_stop", "camera stopped", _camera_debug_snapshot())


func _deactivate_camera_textures() -> void:
	if _camera_texture != null:
		_camera_texture.camera_is_active = false
	if _camera_cbcr_texture != null:
		_camera_cbcr_texture.camera_is_active = false
	if _camera_preview != null:
		_camera_preview.texture = null
	_camera_texture = null
	_camera_cbcr_texture = null
	_active_feed = null
	if _camera_material != null:
		_camera_material.set_shader_parameter("color_mode", 0)


func _selected_camera_feed_id() -> int:
	if _camera_selector == null:
		return -1
	var index := _camera_selector.selected
	if index < 0 or index >= _camera_feeds.size():
		return -1
	return _camera_feeds[index].get_id()


func _on_camera_selector_changed(index: int) -> void:
	if _rebuilding_camera_selector:
		return
	if index < 0 or index >= _camera_feeds.size():
		return
	_camera_requested_feed_id = _camera_feeds[index].get_id()
	_telemetry_event("camera_selection", "camera selection changed", {
		"feed_id": _camera_requested_feed_id,
		"position": _feed_position_name(_camera_feeds[index].get_position()),
	})
	if _camera_texture != null:
		call_deferred("_start_camera")


func _on_camera_view_changed(_index: int) -> void:
	_apply_camera_preview_transform()
	if _active_feed != null:
		_telemetry_event("camera_preview_config", "camera preview transform changed", {
			"feed": _active_feed.get_name(),
			"position": _feed_position_name(_active_feed.get_position()),
			"rotation": _rotation_degrees(),
			"mirror": _mirror_enabled(),
			"flip_y": _feed_flip_y(),
			"feed_transform": str(_active_feed.get_transform()),
		})


func _apply_camera_preview_transform() -> void:
	if _camera_material == null:
		return
	_camera_material.set_shader_parameter("rotation_quarters", _rotation_quarters())
	_camera_material.set_shader_parameter("mirror_x", _mirror_enabled())
	_camera_material.set_shader_parameter("flip_y", _feed_flip_y())


func _rotation_quarters() -> int:
	if _camera_rotation == null:
		return 0
	if _camera_rotation.selected == 0:
		return _auto_rotation_quarters()
	return clampi(_camera_rotation.selected - 1, 0, 3)


func _auto_rotation_quarters() -> int:
	if _active_feed == null:
		return 0
	var radians := _active_feed.get_transform().get_rotation()
	return posmod(int(round(radians / (PI * 0.5))), 4)


func _rotation_degrees() -> int:
	return _rotation_quarters() * 90


func _mirror_enabled() -> bool:
	if _camera_mirror == null:
		return false
	if _camera_mirror.selected == 1:
		return false
	if _camera_mirror.selected == 2:
		return true
	return _active_feed != null and int(_active_feed.get_position()) == 1


func _feed_flip_y() -> bool:
	if _active_feed == null:
		return false
	return _active_feed.get_transform().y.y < 0.0


func _camera_debug_snapshot() -> Dictionary:
	var viewport := get_viewport_rect().size
	return {
		"monitoring_feeds": CameraServer.monitoring_feeds,
		"godot_feed_count": CameraServer.get_feed_count(),
		"cached_feed_count": _camera_feeds.size(),
		"selected_feed_id": _camera_requested_feed_id,
		"active_feed_id": _active_feed.get_id() if _active_feed != null else -1,
		"viewport_logical": [viewport.x, viewport.y],
		"page_visible": is_visible_in_tree(),
	}


func _feed_position_name(position: int) -> String:
	match int(position):
		1:
			return "Front"
		2:
			return "Rear"
		_:
			return "Unspecified"


func _datatype_name(datatype: int) -> String:
	match datatype:
		1:
			return "RGB"
		2:
			return "YCbCr"
		3:
			return "Y+CbCr"
		4:
			return "External"
		_:
			return "No image"


func _start_microphone() -> void:
	if _mic_player != null and _mic_player.playing:
		_mic_status.text = "already running"
		_telemetry_event("microphone_state", "microphone capture already running")
		return

	const BUS_NAME := "IOSLabMic"

	_mic_bus_index = AudioServer.get_bus_index(BUS_NAME)
	if _mic_bus_index < 0:
		AudioServer.add_bus()
		_mic_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_mic_bus_index, BUS_NAME)

	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.25
	AudioServer.add_bus_effect(_mic_bus_index, _capture, 0)
	AudioServer.set_bus_mute(_mic_bus_index, true)

	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS_NAME
	add_child(_mic_player)
	_mic_player.play()

	_mic_status.text = "capture started · waiting for samples"
	_telemetry_event("microphone_start", "muted microphone level capture started")


func _stop_microphone() -> void:
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null

	if _mic_bus_index >= 0:
		while AudioServer.get_bus_effect_count(_mic_bus_index) > 0:
			AudioServer.remove_bus_effect(_mic_bus_index, 0)

	_capture = null
	_mic_level.text = "—"
	_mic_status.text = "stopped"
	_telemetry_event("microphone_stop", "microphone capture stopped")


func _refresh_system_info() -> void:
	if _ioslab != null and _ioslab.has_method("get_battery_level") and _ioslab.has_method("get_battery_state"):
		var level := float(_ioslab.call("get_battery_level"))
		var state := int(_ioslab.call("get_battery_state"))
		if level >= 0.0:
			_power.text = "%d%% · %s" % [int(round(level * 100.0)), _battery_state_name(state)]
		else:
			_power.text = "unknown · %s" % _battery_state_name(state)
	else:
		_power.text = "iOS bridge unavailable"

	var timezone := Time.get_time_zone_from_system()
	_locale.text = "%s · %s" % [
		TranslationServer.get_locale(),
		str(timezone.get("name", "timezone"))
	]


func _battery_state_name(state: int) -> String:
	match state:
		1:
			return "unplugged"
		2:
			return "charging"
		3:
			return "full"
		_:
			return "unknown"


func _copy_test_text() -> void:
	DisplayServer.clipboard_set("Hello from iOS Godot Lab")
	_clipboard_status.text = "test text copied"
	_telemetry_event("clipboard_write", "test text copied to clipboard")


func _read_clipboard() -> void:
	var value := DisplayServer.clipboard_get()
	_clipboard_status.text = value.left(80) if not value.is_empty() else "clipboard empty"
	_telemetry_event("clipboard_read", "clipboard read completed", {"empty": value.is_empty()})


func _vibrate() -> void:
	Input.vibrate_handheld(150)
	_haptic_status.text = "request sent"
	_telemetry_event("haptic", "150 ms vibration requested")


func _open_settings() -> void:
	_telemetry_event("open_settings", "open iOS app settings requested")
	OS.shell_open("app-settings:")


func _telemetry_event(kind: String, message: String, data: Dictionary = {}) -> void:
	var telemetry := get_tree().get_first_node_in_group("ios_lab_telemetry")
	if telemetry != null and telemetry.has_method("record_event"):
		telemetry.call("record_event", kind, message, data)
