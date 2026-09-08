extends VBoxContainer

signal navigate_requested(page_name: String)

const UI = preload("res://scripts/ui.gd")


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	UI.section_title(
		self,
		"More",
		"Additional device and transport tools."
	)

	var tools := UI.make_card(self, "TOOLS")

	var network := UI.button("Network")
	network.pressed.connect(func() -> void: navigate_requested.emit("Network"))
	tools.add_child(network)

	var device := UI.button("Device")
	device.pressed.connect(func() -> void: navigate_requested.emit("Device"))
	tools.add_child(device)

	var note := UI.make_card(
		self,
		"ABOUT THIS LAYOUT",
		"On iPhone the five primary destinations stay in the bottom tab bar. Network and Device live here so the tab bar never overflows. On iPad the full navigation is shown in a sidebar."
	)
	note.add_child(UI.label("The content area keeps its own vertical scroll position and respects the iOS safe area.", 14, UI.MUTED))
