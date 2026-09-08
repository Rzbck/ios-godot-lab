extends RefCounted

# iOS Lab visual system.
# The app uses a 390x844 logical iPhone viewport, so these values are treated
# like point-sized UI measurements rather than desktop pixels.
const BG := Color("000202")
const SURFACE := Color("080c0f")
const SURFACE_ALT := Color("05080a")
const GLASS := Color(0.035, 0.050, 0.058, 0.90)
const BORDER := Color("1d2a30")
const BORDER_SOFT := Color("11191d")
const TEXT := Color("f4f7f8")
const MUTED := Color("8f9ba1")
const ACCENT := Color("71f0c4")
const ACCENT_DIM := Color("16362f")
const GOOD := Color("76dfa5")
const WARN := Color("efc76b")
const BAD := Color("ff7d86")

const BODY_SIZE := 16
const SECONDARY_SIZE := 14
const CAPTION_SIZE := 11
const CONTROL_SIZE := 15
const CONTROL_HEIGHT := 50.0


static func label(text_value: String, size: int = BODY_SIZE, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func single_line_label(text_value: String, size: int = BODY_SIZE, color: Color = TEXT) -> Label:
	var node := label(text_value, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	return node


static func code_label(text_value: String) -> Label:
	var node := label(text_value, 13, ACCENT)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("020506")
	panel.border_color = BORDER_SOFT
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	node.add_theme_stylebox_override("normal", panel)
	return node


static func badge(text_value: String, color: Color = ACCENT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.name = "Badge"
	_set_badge_style(panel, color)
	var text := single_line_label(text_value, 11, color)
	text.name = "Text"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(text)
	return panel


static func set_badge(panel: PanelContainer, text_value: String, color: Color) -> void:
	if panel == null:
		return
	_set_badge_style(panel, color)
	var text := panel.get_node_or_null("Text") as Label
	if text != null:
		text.text = text_value
		text.add_theme_color_override("font_color", color)


static func _set_badge_style(panel: PanelContainer, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.075)
	style.border_color = Color(color, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)


static func glass_panel(radius: int = 20) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = GLASS
	style.border_color = Color("1d2a30")
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", style)
	return panel


static func tab_button(text_value: String) -> Button:
	var node := Button.new()
	node.text = text_value
	node.toggle_mode = true
	node.custom_minimum_size = Vector2(0, 56)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", 12)
	node.add_theme_color_override("font_color", MUTED)
	node.add_theme_color_override("font_pressed_color", TEXT)
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_color = Color(0, 0, 0, 0)
	normal.set_border_width_all(0)
	normal.set_corner_radius_all(16)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.10)
	pressed.border_color = Color(ACCENT, 0.24)
	pressed.set_border_width_all(1)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("hover_pressed", pressed)
	return node


static func side_nav_button(text_value: String) -> Button:
	var node := Button.new()
	node.text = text_value
	node.toggle_mode = true
	node.custom_minimum_size = Vector2(0, 48)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", 15)
	node.add_theme_color_override("font_color", MUTED)
	node.add_theme_color_override("font_pressed_color", TEXT)
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_color = Color(0, 0, 0, 0)
	normal.set_border_width_all(0)
	normal.set_corner_radius_all(13)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.10)
	pressed.border_color = Color(ACCENT, 0.22)
	pressed.set_border_width_all(1)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("hover_pressed", pressed)
	return node


# Compatibility helper for older page code.
static func nav_button(text_value: String) -> Button:
	return side_nav_button(text_value)


static func set_nav_active(node: Button, active: bool) -> void:
	if node != null:
		node.set_pressed_no_signal(active)


static func make_card(parent: Container, title_text: String, description: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Content surfaces never swallow the parent vertical scroll gesture.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.border_color = BORDER_SOFT
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 15
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)

	var title := label(title_text, 16, TEXT)
	content.add_child(title)

	if not description.is_empty():
		content.add_child(label(description, SECONDARY_SIZE, MUTED))

	return content


static func value_row(parent: Container, key: String, value: String = "—") -> Label:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var key_label := single_line_label(key.to_upper(), CAPTION_SIZE, MUTED)
	key_label.custom_minimum_size.x = 96
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(key_label)

	var value_label := label(value, 15, TEXT)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	return value_label


static func button(text_value: String, accent: bool = false) -> Button:
	var node := Button.new()
	node.text = text_value
	node.custom_minimum_size.y = CONTROL_HEIGHT
	node.add_theme_font_size_override("font_size", CONTROL_SIZE)
	node.add_theme_color_override("font_color", TEXT)
	node.focus_mode = Control.FOCUS_ALL
	# PASS lets ScrollContainer keep receiving a drag that begins on a control.
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("0b1114") if not accent else Color(ACCENT, 0.11)
	normal.border_color = BORDER if not accent else Color(ACCENT, 0.48)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	node.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("10191d") if not accent else Color(ACCENT, 0.16)
	node.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("152227") if not accent else Color(ACCENT, 0.22)
	node.add_theme_stylebox_override("pressed", pressed)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(ACCENT, 0.65)
	node.add_theme_stylebox_override("focus", focus)
	return node


static func line_edit(placeholder: String = "") -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = CONTROL_HEIGHT
	node.add_theme_font_size_override("font_size", 16)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.72))
	node.add_theme_color_override("caret_color", ACCENT)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.add_theme_stylebox_override("normal", _input_style(false))
	node.add_theme_stylebox_override("focus", _input_style(true))
	return node


static func text_edit(placeholder: String = "", min_height: float = 132.0) -> TextEdit:
	var node := TextEdit.new()
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = min_height
	node.add_theme_font_size_override("font_size", 15)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.72))
	node.add_theme_color_override("caret_color", ACCENT)
	node.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	node.add_theme_stylebox_override("normal", _input_style(false))
	node.add_theme_stylebox_override("focus", _input_style(true))
	return node


static func option_button(items: Array) -> OptionButton:
	var node := OptionButton.new()
	for item in items:
		node.add_item(str(item))
	node.custom_minimum_size.y = CONTROL_HEIGHT
	node.add_theme_font_size_override("font_size", CONTROL_SIZE)
	node.add_theme_color_override("font_color", TEXT)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	var normal := _input_style(false)
	var focus := _input_style(true)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)
	node.add_theme_stylebox_override("pressed", focus)
	node.add_theme_stylebox_override("focus", focus)
	return node


static func terminal_log(min_height: float = 190.0) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.custom_minimum_size.y = min_height
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.fit_content = false
	node.scroll_active = true
	node.scroll_following = true
	node.add_theme_font_size_override("normal_font_size", 13)
	node.add_theme_color_override("default_color", Color("c1ced2"))
	node.add_theme_stylebox_override("normal", _input_style(false))
	return node


static func section_title(parent: Container, title_text: String, subtitle: String = "") -> void:
	var title := label(title_text, 25, TEXT)
	parent.add_child(title)
	if not subtitle.is_empty():
		parent.add_child(label(subtitle, 14, MUTED))


static func _input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("020607")
	style.border_color = Color(ACCENT, 0.50) if focused else BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(13)
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style
