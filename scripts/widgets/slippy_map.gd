extends VBoxContainer

const UI = preload("res://scripts/ui.gd")
const TILE_SIZE := 256.0
const MIN_ZOOM := 3
const MAX_ZOOM := 18
const TILE_USER_AGENT := "ios-godot-lab/0.2 (personal capability lab)"

var _zoom := 15
var _latitude := 0.0
var _longitude := 0.0
var _have_fix := false
var _last_center := Vector2(999.0, 999.0)
var _generation := 0

var _map_view: Control
var _tile_layer: Control
var _status: Label
var _zoom_label: Label
var _marker: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var toolbar := HBoxContainer.new()
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toolbar)

	_status = UI.label("Waiting for GPS fix", 13, UI.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_status)

	var minus := UI.button("−")
	minus.custom_minimum_size = Vector2(48, 42)
	minus.pressed.connect(_change_zoom.bind(-1))
	toolbar.add_child(minus)

	_zoom_label = UI.label("z15", 13, UI.MUTED)
	_zoom_label.custom_minimum_size.x = 42
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(_zoom_label)

	var plus := UI.button("+")
	plus.custom_minimum_size = Vector2(48, 42)
	plus.pressed.connect(_change_zoom.bind(1))
	toolbar.add_child(plus)

	var frame := PanelContainer.new()
	frame.custom_minimum_size.y = 330
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true

	var style := StyleBoxFlat.new()
	style.bg_color = Color("0d141d")
	style.border_color = UI.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	_map_view = Control.new()
	_map_view.custom_minimum_size.y = 330
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.clip_contents = true
	frame.add_child(_map_view)

	_tile_layer = Control.new()
	_tile_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(_tile_layer)

	var waiting := UI.label("GPS MAP\nTiles load after the first location fix.", 16, UI.MUTED)
	waiting.name = "Waiting"
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	waiting.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_view.add_child(waiting)

	_marker = UI.label("●", 30, UI.BAD)
	_marker.visible = false
	_marker.z_index = 50
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(_marker)

	var attribution := UI.label("© OpenStreetMap contributors", 11, UI.MUTED)
	attribution.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(attribution)

	_map_view.resized.connect(_on_map_resized)


func set_location(latitude: float, longitude: float, force: bool = false) -> void:
	var next := Vector2(latitude, longitude)
	var moved := next.distance_to(_last_center)

	_latitude = clamp(latitude, -85.05112878, 85.05112878)
	_longitude = wrapf(longitude, -180.0, 180.0)
	_have_fix = true
	_status.text = "%.6f, %.6f" % [_latitude, _longitude]

	var waiting := _map_view.get_node_or_null("Waiting")
	if waiting != null:
		waiting.visible = false
	_marker.visible = true

	if force or moved > 0.00018:
		_last_center = next
		call_deferred("_refresh_map")
	else:
		_position_marker()


func _change_zoom(delta: int) -> void:
	_zoom = clampi(_zoom + delta, MIN_ZOOM, MAX_ZOOM)
	_zoom_label.text = "z%d" % _zoom
	if _have_fix:
		call_deferred("_refresh_map")


func _on_map_resized() -> void:
	if _have_fix:
		call_deferred("_refresh_map")


func _refresh_map() -> void:
	if not _have_fix or not is_instance_valid(_map_view):
		return
	if _map_view.size.x < 20.0 or _map_view.size.y < 20.0:
		return

	_generation += 1
	var generation := _generation

	for child in _tile_layer.get_children():
		child.queue_free()

	var world := _latlon_to_world_pixels(_latitude, _longitude, _zoom)
	var center_tile_x := int(floor(world.x / TILE_SIZE))
	var center_tile_y := int(floor(world.y / TILE_SIZE))
	var tile_count := 1 << _zoom

	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var raw_x := center_tile_x + offset_x
			var raw_y := center_tile_y + offset_y
			if raw_y < 0 or raw_y >= tile_count:
				continue

			var wrapped_x := ((raw_x % tile_count) + tile_count) % tile_count
			var rect := TextureRect.new()
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.position = Vector2(
				raw_x * TILE_SIZE - world.x + _map_view.size.x * 0.5,
				raw_y * TILE_SIZE - world.y + _map_view.size.y * 0.5
			)
			rect.size = Vector2(TILE_SIZE, TILE_SIZE)
			_tile_layer.add_child(rect)

			var cache_path := "user://map_cache/%d_%d_%d.png" % [_zoom, wrapped_x, raw_y]
			if FileAccess.file_exists(cache_path):
				_load_cached_tile(cache_path, rect)
			else:
				_request_tile(_zoom, wrapped_x, raw_y, generation, rect, cache_path)

	_position_marker()


func _request_tile(zoom: int, x: int, y: int, generation: int, rect: TextureRect, cache_path: String) -> void:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	request.request_completed.connect(_on_tile_loaded.bind(generation, rect, cache_path, request))

	var url := "https://tile.openstreetmap.org/%d/%d/%d.png" % [zoom, x, y]
	var headers := [
		"User-Agent: %s" % TILE_USER_AGENT,
		"Accept: image/png",
	]
	var error := request.request(url, headers)
	if error != OK:
		request.queue_free()


func _on_tile_loaded(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	generation: int,
	rect: TextureRect,
	cache_path: String,
	request: HTTPRequest
) -> void:
	if is_instance_valid(request):
		request.queue_free()
	if generation != _generation:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	if not is_instance_valid(rect):
		return

	var image := Image.new()
	if image.load_png_from_buffer(body) != OK:
		return

	rect.texture = ImageTexture.create_from_image(image)
	_ensure_cache_dir()
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(body)


func _load_cached_tile(cache_path: String, rect: TextureRect) -> void:
	var file := FileAccess.open(cache_path, FileAccess.READ)
	if file == null:
		return
	var body := file.get_buffer(file.get_length())
	var image := Image.new()
	if image.load_png_from_buffer(body) == OK:
		rect.texture = ImageTexture.create_from_image(image)


func _ensure_cache_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("map_cache"):
		dir.make_dir("map_cache")


func _position_marker() -> void:
	if not _have_fix or not is_instance_valid(_marker):
		return
	_marker.position = Vector2(
		_map_view.size.x * 0.5 - 11.0,
		_map_view.size.y * 0.5 - 22.0
	)


func _latlon_to_world_pixels(latitude: float, longitude: float, zoom: int) -> Vector2:
	var n := float(1 << zoom)
	var x_tile := (longitude + 180.0) / 360.0 * n
	var lat_rad := deg_to_rad(latitude)
	var y_tile := (1.0 - asinh(tan(lat_rad)) / PI) * 0.5 * n
	return Vector2(x_tile * TILE_SIZE, y_tile * TILE_SIZE)
