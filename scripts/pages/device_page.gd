extends VBoxContainer

const UI = preload("res://scripts/ui.gd")

var _camera_status: Label
var _camera_preview: TextureRect
var _camera_texture: CameraTexture

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
	add_theme_constant_override("separation", 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if OS.get_name() == "iOS" and Engine.has_singleton("IOSLab"):
		_ioslab = Engine.get_singleton("IOSLab")
	else:
		_ioslab = null

	UI.section_title(
		self,
		"Device",
		"Camera, microphone, battery, clipboard and system-level probes exposed by Godot and the IOSLab bridge on iOS."
	)

	_build_camera_card()
	_build_microphone_card()
	_build_system_card()

	set_process(true)
	_refresh_system_info()


func _build_camera_card() -> void:
	var card := UI.make_card(
		self,
		"CAMERA",
		"Starts the first camera feed exposed by Godot's iOS camera module. iOS may ask for camera permission."
	)
	_camera_status = UI.value_row(card, "Status", "not started")

	_camera_preview = TextureRect.new()
	_camera_preview.custom_minimum_size.y = 280
	_camera_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camera_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_camera_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_camera_preview)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	card.add_child(buttons)

	var refresh := UI.button("START / REFRESH", true)
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.pressed.connect(_start_camera)
	buttons.add_child(refresh)

	var stop := UI.button("STOP")
	stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop.pressed.connect(_stop_camera)
	buttons.add_child(stop)


func _build_microphone_card() -> void:
	var card := UI.make_card(
		self,
		"MICROPHONE",
		"Starts a muted capture bus and displays the live RMS level. Audio is not saved or transmitted."
	)
	_mic_status = UI.value_row(card, "Status", "not started")
	_mic_level = UI.value_row(card, "Level", "—")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	card.add_child(buttons)

	var start := UI.button("START MIC", true)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_start_microphone)
	buttons.add_child(start)

	var stop := UI.button("STOP")
	stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop.pressed.connect(_stop_microphone)
	buttons.add_child(stop)


func _build_system_card() -> void:
	var card := UI.make_card(self, "SYSTEM")
	_power = UI.value_row(card, "Battery", "reading…")
	_locale = UI.value_row(card, "Locale", "reading…")
	UI.value_row(card, "Model", OS.get_model_name())
	UI.value_row(card, "OS", OS.get_name())

	var actions := UI.make_card(
		self,
		"DEVICE ACTIONS",
		"Useful small APIs for app integration tests."
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
	settings.pressed.connect(func() -> void: OS.shell_open("app-settings:"))
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


func _start_camera() -> void:
	CameraServer.monitoring_feeds = true
	_camera_status.text = "requesting camera / waiting for feeds…"
	await get_tree().create_timer(0.6).timeout

	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		_camera_status.text = "no feeds · permission/module may be unavailable"
		return

	var feed := feeds[0] as CameraFeed
	if feed == null:
		_camera_status.text = "invalid camera feed"
		return

	_camera_texture = CameraTexture.new()
	_camera_texture.camera_feed_id = feed.get_id()
	_camera_texture.camera_is_active = true
	_camera_preview.texture = _camera_texture
	_camera_status.text = "%s · active" % feed.get_name()


func _stop_camera() -> void:
	if _camera_texture != null:
		_camera_texture.camera_is_active = false
	_camera_preview.texture = null
	_camera_texture = null
	CameraServer.monitoring_feeds = false
	_camera_status.text = "stopped"


func _start_microphone() -> void:
	if _mic_player != null and _mic_player.playing:
		_mic_status.text = "already running"
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


func _read_clipboard() -> void:
	var value := DisplayServer.clipboard_get()
	_clipboard_status.text = value.left(80) if not value.is_empty() else "clipboard empty"


func _vibrate() -> void:
	Input.vibrate_handheld(150)
	_haptic_status.text = "request sent"
