extends RefCounted

# iOS Lab visual system: near-black content surfaces + restrained glass only for
# navigation/controls. Sizes keep interactive controls at the iOS 44 pt target.
const BG := Color("020405")
const SURFACE := Color("090d10")
const SURFACE_ALT := Color("06090c")
const GLASS := Color(0.045, 0.060, 0.070, 0.82)
const BORDER := Color("1b2a31")
const BORDER_SOFT := Color("111b20")
const TEXT := Color("eef3f5")
const MUTED := Color("81919a")
const ACCENT := Color("72f0c4")
const ACCENT_DIM := Color("183b33")
const GOOD := Color("78e0a6")
const WARN := Color("f0c96e")
const BAD := Color("ff7e86")


static func label(text_value: String, size: int = 14, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func code_label(text_value: String) -> Label:
	var node := label(text_value, 12, ACCENT)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_constant_override("outline_size", 0)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("030607")
	panel.border_color = BORDER_SOFT
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	node.add_theme_stylebox_override("normal", panel)
	return node


static func badge(text_value: String, color: Color = ACCENT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.name = "Badge"
	_set_badge_style(panel, color)
	var text := label(text_value, 11, color)
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
	style.border_color = Color(color, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)


static func glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = GLASS
	style.border_color = Color("203139")
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel


static func nav_button(text_value: String) -> Button:
	var node := Button.new()
	node.text = text_value
	node.toggle_mode = true
	node.custom_minimum_size = Vector2(92, 44)
	node.add_theme_font_size_override("font_size", 12)
	node.add_theme_color_override("font_color", MUTED)
	node.add_theme_color_override("font_pressed_color", TEXT)
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.03, 0.035, 0.32)
	normal.border_color = Color(0, 0, 0, 0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(13)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.10)
	pressed.border_color = Color(ACCENT, 0.34)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("hover_pressed", pressed)
	return node


static func set_nav_active(node: Button, active: bool) -> void:
	node.set_pressed_no_signal(active)


static func make_card(parent: Container, title_text: String, description: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Critical on iPhone: content surfaces never swallow the parent scroll drag.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.border_color = BORDER_SOFT
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 13
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)

	var title := label(title_text, 14, TEXT)
	title.add_theme_color_override("font_color", TEXT)
	content.add_child(title)

	if not description.is_empty():
		var help := label(description, 12, MUTED)
		content.add_child(help)

	return content


static func value_row(parent: Container, key: String, value: String = "—") -> Label:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var key_label := label(key.to_upper(), 11, MUTED)
	key_label.custom_minimum_size.x = 116
	row.add_child(key_label)

	var value_label := label(value, 12, TEXT)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return value_label


static func button(text_value: String, accent: bool = false) -> Button:
	var node := Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size", 12)
	node.add_theme_color_override("font_color", TEXT)
	node.focus_mode = Control.FOCUS_ALL
	# PASS lets ScrollContainer keep receiving a drag that begins on a control.
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("0c1317") if not accent else Color(ACCENT, 0.11)
	normal.border_color = BORDER if not accent else Color(ACCENT, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	node.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("111b20") if not accent else Color(ACCENT, 0.17)
	node.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("16262c") if not accent else Color(ACCENT, 0.22)
	node.add_theme_stylebox_override("pressed", pressed)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(ACCENT, 0.70)
	node.add_theme_stylebox_override("focus", focus)
	return node


static func line_edit(placeholder: String = "") -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size", 12)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.72))
	node.add_theme_color_override("caret_color", ACCENT)
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := _input_style(false)
	var focus := _input_style(true)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("focus", focus)
	return node


static func text_edit(placeholder: String = "", min_height: float = 120.0) -> TextEdit:
	var node := TextEdit.new()
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = min_height
	node.add_theme_font_size_override("font_size", 12)
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
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size", 12)
	node.add_theme_color_override("font_color", TEXT)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	var normal := _input_style(false)
	var focus := _input_style(true)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)
	node.add_theme_stylebox_override("pressed", focus)
	node.add_theme_stylebox_override("focus", focus)
	return node


static func terminal_log(min_height: float = 160.0) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.custom_minimum_size.y = min_height
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.fit_content = false
	node.scroll_active = true
	node.scroll_following = true
	node.add_theme_font_size_override("normal_font_size", 11)
	node.add_theme_color_override("default_color", Color("b8c7cb"))
	node.add_theme_stylebox_override("normal", _input_style(false))
	return node


static func section_title(parent: Container, title_text: String, subtitle: String = "") -> void:
	var eyebrow := label("IOSLAB // RUNTIME", 11, ACCENT)
	parent.add_child(eyebrow)
	var title := label(title_text, 22, TEXT)
	parent.add_child(title)
	if not subtitle.is_empty():
		parent.add_child(label(subtitle, 13, MUTED))


static func _input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("030708")
	style.border_color = Color(ACCENT, 0.56) if focused else BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 11
	style.content_margin_right = 11
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style
