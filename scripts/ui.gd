extends RefCounted

const BG := Color("090e16")
const CARD := Color("151c27")
const CARD_ALT := Color("111923")
const BORDER := Color("263247")
const TEXT := Color("f3f6fb")
const MUTED := Color("9ca8b8")
const ACCENT := Color("78a9ff")
const GOOD := Color("75d49b")
const WARN := Color("f3c96b")
const BAD := Color("ef7777")


static func label(text_value: String, size: int = 17, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func badge(text_value: String, color: Color = ACCENT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.10)
	style.border_color = Color(color, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	var text := label(text_value, 13, color)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(text)
	return panel


static func nav_button(text_value: String) -> Button:
	var node := Button.new()
	node.text = text_value
	node.toggle_mode = true
	node.custom_minimum_size = Vector2(108, 44)
	node.add_theme_font_size_override("font_size", 14)
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := StyleBoxFlat.new()
	normal.bg_color = CARD_ALT
	normal.border_color = BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("1d3150")
	pressed.border_color = ACCENT
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("hover_pressed", pressed)
	return node


static func set_nav_active(node: Button, active: bool) -> void:
	node.set_pressed_no_signal(active)


static func make_card(parent: Container, title_text: String, description: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Critical for iPhone scrolling: cards must not swallow drags.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 20
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)

	var title := label(title_text, 19, TEXT)
	content.add_child(title)

	if not description.is_empty():
		var help := label(description, 14, MUTED)
		content.add_child(help)

	return content


static func value_row(parent: Container, key: String, value: String = "—") -> Label:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var key_label := label(key, 15, MUTED)
	key_label.custom_minimum_size.x = 142
	row.add_child(key_label)

	var value_label := label(value, 15, TEXT)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return value_label


static func button(text_value: String, accent: bool = false) -> Button:
	var node := Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 52
	node.add_theme_font_size_override("font_size", 15)
	node.focus_mode = Control.FOCUS_ALL
	# PASS lets ScrollContainer keep receiving a drag that begins on a button.
	node.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("1f2b3d") if not accent else Color("23446e")
	normal.border_color = Color("33445e") if not accent else ACCENT
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(15)
	node.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("293850") if not accent else Color("2c558a")
	node.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("36527a")
	node.add_theme_stylebox_override("pressed", pressed)
	return node


static func line_edit(placeholder: String = "") -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = 48
	node.add_theme_font_size_override("font_size", 15)
	return node


static func text_edit(placeholder: String = "", min_height: float = 120.0) -> TextEdit:
	var node := TextEdit.new()
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = min_height
	node.add_theme_font_size_override("font_size", 14)
	node.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return node


static func section_title(parent: Container, title_text: String, subtitle: String = "") -> void:
	var title := label(title_text, 27, TEXT)
	parent.add_child(title)
	if not subtitle.is_empty():
		parent.add_child(label(subtitle, 15, MUTED))
