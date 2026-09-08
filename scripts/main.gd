extends Control

const UI = preload("res://scripts/ui.gd")
const TelemetryService = preload("res://scripts/services/telemetry_service.gd")
const TrackService = preload("res://scripts/services/track_service.gd")
const StreamRouter = preload("res://scripts/services/stream_router.gd")
const OverviewPage = preload("res://scripts/pages/overview_page.gd")
const TelemetryPage = preload("res://scripts/pages/telemetry_page.gd")
const SensorsPage = preload("res://scripts/pages/sensors_page.gd")
const LocationPage = preload("res://scripts/pages/location_page.gd")
const NetworkPage = preload("res://scripts/pages/network_page.gd")
const DevicePage = preload("res://scripts/pages/device_page.gd")
const MorePage = preload("res://scripts/pages/more_page.gd")

const PHONE_TABS := ["Overview", "Telemetry", "Sensors", "GPS", "More"]
const TABLET_NAV := ["Overview", "Telemetry", "Sensors", "GPS", "Network", "Device"]
const ALL_PAGES := ["Overview", "Telemetry", "Sensors", "GPS", "More", "Network", "Device"]
const DISPLAY_NAMES := {
	"Overview": "Home",
	"Telemetry": "Telemetry",
	"Sensors": "Motion",
	"GPS": "Location",
	"More": "More",
	"Network": "Live Output",
	"Device": "Device",
}

var _telemetry: Node
var _track: Node
var _router: Node
var _telemetry_badge: PanelContainer
var _page_title: Label
var _page_scroll: ScrollContainer
var _page_host: VBoxContainer
var _nav_buttons: Dictionary = {}
var _pages: Dictionary = {}
var _layout_mode := "phone"
var _safe_margins := {"left": 12, "right": 12, "top": 8, "bottom": 8}


func _ready() -> void:
	_telemetry = TelemetryService.new()
	_telemetry.name = "TelemetryService"
	add_child(_telemetry)
	_telemetry.status_changed.connect(_on_telemetry_status_changed)

	_track = TrackService.new()
	_track.name = "TrackService"
	add_child(_track)

	_router = StreamRouter.new()
	_router.name = "StreamRouter"
	add_child(_router)

	_layout_mode = "tablet" if get_viewport_rect().size.x >= 600.0 else "phone"
	_safe_margins = _compute_safe_margins()

	_build_shell()
	_register_pages()
	_show_page("Overview")
	_record_layout_probe()


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = UI.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", int(_safe_margins.get("left", 12)))
	safe.add_theme_constant_override("margin_right", int(_safe_margins.get("right", 12)))
	safe.add_theme_constant_override("margin_top", int(_safe_margins.get("top", 8)))
	safe.add_theme_constant_override("margin_bottom", int(_safe_margins.get("bottom", 8)))
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)

	if _layout_mode == "tablet":
		_build_tablet_shell(safe)
	else:
		_build_phone_shell(safe)


func _build_phone_shell(parent: Container) -> void:
	var shell := VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 8)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shell)

	_build_top_bar(shell)
	_build_page_scroll(shell)
	_build_phone_tab_bar(shell)


func _build_tablet_shell(parent: Container) -> void:
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(body)

	_build_tablet_sidebar(body)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(detail)

	_build_top_bar(detail)
	_build_page_scroll(detail)


func _build_top_bar(parent: Container) -> void:
	var panel := UI.glass_panel(16)
	panel.custom_minimum_size.y = 54
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_page_title = UI.single_line_label("Home", 22, UI.TEXT)
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_page_title)

	_telemetry_badge = UI.badge("TEL OFF", UI.MUTED)
	_telemetry_badge.custom_minimum_size.x = 64
	row.add_child(_telemetry_badge)


func _build_phone_tab_bar(parent: Container) -> void:
	var bar := UI.glass_panel(21)
	bar.custom_minimum_size.y = 66
	parent.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(margin)

	var tabs := HBoxContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", 2)
	tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(tabs)

	for page_name in PHONE_TABS:
		var button := UI.tab_button(str(DISPLAY_NAMES.get(page_name, page_name)))
		button.pressed.connect(_show_page.bind(page_name))
		_nav_buttons[page_name] = button
		tabs.add_child(button)


func _build_tablet_sidebar(parent: Container) -> void:
	var sidebar := UI.glass_panel(22)
	sidebar.custom_minimum_size.x = 212
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(sidebar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar.add_child(margin)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(stack)

	stack.add_child(UI.single_line_label("iOS Lab", 23, UI.TEXT))
	stack.add_child(UI.single_line_label("DEVICE CONSOLE", 11, UI.ACCENT))

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(spacer)

	for page_name in TABLET_NAV:
		var button := UI.side_nav_button(str(DISPLAY_NAMES.get(page_name, page_name)))
		button.pressed.connect(_show_page.bind(page_name))
		_nav_buttons[page_name] = button
		stack.add_child(button)

	var flex := Control.new()
	flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(flex)

	var build := _read_build_info()
	var sha := str(build.get("git_sha", "LOCAL"))
	if sha.length() > 8:
		sha = sha.left(8)
	stack.add_child(UI.single_line_label("build %s" % sha, 11, UI.MUTED))


func _build_page_scroll(parent: Container) -> void:
	_page_scroll = ScrollContainer.new()
	_page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_page_scroll.scroll_deadzone = 4
	_page_scroll.scroll_hint_mode = ScrollContainer.SCROLL_HINT_MODE_BOTTOM_AND_RIGHT
	_page_scroll.follow_focus = true
	parent.add_child(_page_scroll)

	var page_margin := MarginContainer.new()
	page_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_margin.add_theme_constant_override("margin_left", 2)
	page_margin.add_theme_constant_override("margin_right", 2)
	page_margin.add_theme_constant_override("margin_top", 8)
	page_margin.add_theme_constant_override("margin_bottom", 18)
	page_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_scroll.add_child(page_margin)

	_page_host = VBoxContainer.new()
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.add_theme_constant_override("separation", 14)
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_margin.add_child(_page_host)


func _register_pages() -> void:
	var overview := OverviewPage.new()
	overview.navigate_requested.connect(_show_page)

	var more := MorePage.new()
	more.navigate_requested.connect(_show_page)

	_pages = {
		"Overview": overview,
		"Telemetry": TelemetryPage.new(),
		"Sensors": SensorsPage.new(),
		"GPS": LocationPage.new(),
		"More": more,
		"Network": NetworkPage.new(),
		"Device": DevicePage.new(),
	}

	for page_name in ALL_PAGES:
		var page := _pages[page_name] as Control
		page.visible = false
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_page_host.add_child(page)


func _show_page(page_name: String) -> void:
	if not _pages.has(page_name):
		return

	for name in ALL_PAGES:
		var page := _pages[name] as Control
		page.visible = name == page_name

	var active_nav := page_name
	if _layout_mode == "phone" and not PHONE_TABS.has(page_name):
		active_nav = "More"

	for nav_name in _nav_buttons.keys():
		UI.set_nav_active(_nav_buttons[nav_name] as Button, str(nav_name) == active_nav)

	if _page_title != null:
		_page_title.text = str(DISPLAY_NAMES.get(page_name, page_name))

	if _telemetry != null:
		_telemetry.set_current_page(page_name)

	if is_instance_valid(_page_scroll):
		_page_scroll.set_deferred("scroll_vertical", 0)


func _on_telemetry_status_changed(state: String, _detail: String) -> void:
	if _telemetry_badge == null:
		return

	match state:
		"streaming":
			UI.set_badge(_telemetry_badge, "TEL LIVE", UI.GOOD)
		"connecting", "reconnecting", "fallback":
			UI.set_badge(_telemetry_badge, "TEL LINK", UI.WARN)
		"error":
			UI.set_badge(_telemetry_badge, "TEL ERR", UI.BAD)
		_:
			UI.set_badge(_telemetry_badge, "TEL OFF", UI.MUTED)


func _compute_safe_margins() -> Dictionary:
	var result := {"left": 12, "right": 12, "top": 8, "bottom": 8}
	if OS.get_name() != "iOS":
		if _layout_mode == "tablet":
			return {"left": 20, "right": 20, "top": 16, "bottom": 16}
		return result

	var screen_px := DisplayServer.screen_get_size()
	var safe_px := DisplayServer.get_display_safe_area()
	var viewport := get_viewport_rect().size
	if screen_px.x <= 0 or screen_px.y <= 0:
		return result

	var sx := viewport.x / float(screen_px.x)
	var sy := viewport.y / float(screen_px.y)
	result.left = maxi(10, int(round(safe_px.position.x * sx)))
	result.top = maxi(6, int(round(safe_px.position.y * sy)))
	result.right = maxi(10, int(round((screen_px.x - safe_px.end.x) * sx)))
	result.bottom = maxi(6, int(round((screen_px.y - safe_px.end.y) * sy)))
	return result


func _record_layout_probe() -> void:
	if _telemetry == null or not _telemetry.has_method("record_event"):
		return
	var viewport := get_viewport_rect().size
	var screen_px := DisplayServer.screen_get_size()
	var safe_px := DisplayServer.get_display_safe_area()
	_telemetry.call("record_event", "ui_layout", "responsive iPhone shell initialized", {
		"layout": _layout_mode,
		"viewport_logical": [viewport.x, viewport.y],
		"screen_px": [screen_px.x, screen_px.y],
		"screen_scale": DisplayServer.screen_get_scale(),
		"screen_dpi": DisplayServer.screen_get_dpi(),
		"safe_area_px": [safe_px.position.x, safe_px.position.y, safe_px.size.x, safe_px.size.y],
		"safe_margins_logical": _safe_margins.duplicate(true),
		"phone_tabs": PHONE_TABS.duplicate(),
	})


func _read_build_info() -> Dictionary:
	const PATH := "res://config/build_info.json"
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
