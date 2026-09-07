extends Control

const UI = preload("res://scripts/ui.gd")
const OverviewPage = preload("res://scripts/pages/overview_page.gd")
const SensorsPage = preload("res://scripts/pages/sensors_page.gd")
const LocationPage = preload("res://scripts/pages/location_page.gd")
const NetworkPage = preload("res://scripts/pages/network_page.gd")
const DevicePage = preload("res://scripts/pages/device_page.gd")

const PAGE_ORDER := ["Overview", "Sensors", "GPS", "Network", "Device"]

var _page_scroll: ScrollContainer
var _page_host: VBoxContainer
var _nav_buttons: Dictionary = {}
var _pages: Dictionary = {}


func _ready() -> void:
	_build_shell()
	_register_pages()
	_show_page("Overview")


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = UI.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 18)
	safe.add_theme_constant_override("margin_right", 18)
	safe.add_theme_constant_override("margin_top", 18)
	safe.add_theme_constant_override("margin_bottom", 14)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)

	var shell := VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 12)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(shell)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(header)

	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 0)
	title_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_stack)

	title_stack.add_child(UI.label("IOS · GODOT · DEVICE LAB", 13, UI.ACCENT))
	title_stack.add_child(UI.label("iPhone Lab", 30, UI.TEXT))

	var build := _read_build_info()
	var build_badge := UI.badge("%s · %s" % [
		str(build.get("version", "0.2.0-dev")),
		str(build.get("git_sha", "LOCAL"))
	], UI.MUTED)
	build_badge.custom_minimum_size.y = 34
	header.add_child(build_badge)

	var nav_scroll := ScrollContainer.new()
	nav_scroll.custom_minimum_size.y = 52
	nav_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	nav_scroll.scroll_deadzone = 4
	shell.add_child(nav_scroll)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.mouse_filter = Control.MOUSE_FILTER_PASS
	nav_scroll.add_child(nav)

	for page_name in PAGE_ORDER:
		var button := UI.nav_button(page_name)
		button.pressed.connect(_show_page.bind(page_name))
		_nav_buttons[page_name] = button
		nav.add_child(button)

	_page_scroll = ScrollContainer.new()
	_page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_page_scroll.scroll_deadzone = 3
	_page_scroll.scroll_hint_mode = ScrollContainer.SCROLL_HINT_MODE_BOTTOM_AND_RIGHT
	_page_scroll.follow_focus = true
	shell.add_child(_page_scroll)

	var page_margin := MarginContainer.new()
	page_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_margin.add_theme_constant_override("margin_left", 2)
	page_margin.add_theme_constant_override("margin_right", 2)
	page_margin.add_theme_constant_override("margin_top", 4)
	page_margin.add_theme_constant_override("margin_bottom", 48)
	page_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_scroll.add_child(page_margin)

	_page_host = VBoxContainer.new()
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.add_theme_constant_override("separation", 16)
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_margin.add_child(_page_host)


func _register_pages() -> void:
	_pages = {
		"Overview": OverviewPage.new(),
		"Sensors": SensorsPage.new(),
		"GPS": LocationPage.new(),
		"Network": NetworkPage.new(),
		"Device": DevicePage.new(),
	}

	for page_name in PAGE_ORDER:
		var page := _pages[page_name] as Control
		page.visible = false
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_page_host.add_child(page)


func _show_page(page_name: String) -> void:
	if not _pages.has(page_name):
		return

	for name in PAGE_ORDER:
		var page := _pages[name] as Control
		page.visible = name == page_name

		var button := _nav_buttons[name] as Button
		UI.set_nav_active(button, name == page_name)

	if is_instance_valid(_page_scroll):
		_page_scroll.set_deferred("scroll_vertical", 0)


func _read_build_info() -> Dictionary:
	const PATH := "res://config/build_info.json"
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
