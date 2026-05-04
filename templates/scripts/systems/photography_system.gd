extends Node
## Photography System — screenshot capture with photo book.
## Matches shared/game-engine/rendering/BabylonPhotographySystem.ts, BabylonPhotoBookPanel.ts.

signal photo_taken(path: String)

const PHOTO_DIR := "user://photos/"
const MAX_PHOTOS := 50

var _is_photo_mode := false
var _free_camera: Camera3D = null
var _original_camera: Camera3D = null
var _photo_book_panel: CanvasLayer = null
var _photo_grid: GridContainer = null
var _photos: Array[String] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	_build_photo_book_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("photo_mode"):
		_toggle_photo_mode()
	elif _is_photo_mode and event.is_action_pressed("interact"):
		_capture_photo()
	elif event.is_action_pressed("photo_book"):
		_toggle_photo_book()

func _toggle_photo_mode() -> void:
	_is_photo_mode = not _is_photo_mode
	get_tree().paused = _is_photo_mode

	if _is_photo_mode:
		_original_camera = get_viewport().get_camera_3d()
		_free_camera = Camera3D.new()
		if _original_camera:
			_free_camera.global_transform = _original_camera.global_transform
			_free_camera.fov = _original_camera.fov
		add_child(_free_camera)
		_free_camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		if _free_camera:
			_free_camera.queue_free()
			_free_camera = null
		if _original_camera:
			_original_camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _capture_photo() -> void:
	if _photos.size() >= MAX_PHOTOS:
		print("[Photography] Photo storage full")
		return

	# Unpause briefly for screenshot
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var filename := "photo_%s.png" % timestamp
	var path := PHOTO_DIR + filename
	image.save_png(path)
	_photos.append(path)

	get_tree().paused = true
	photo_taken.emit(path)
	print("[Photography] Photo saved: %s" % path)

func _toggle_photo_book() -> void:
	if _photo_book_panel.visible:
		_photo_book_panel.visible = false
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		_populate_photo_grid()
		_photo_book_panel.visible = true
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _build_photo_book_ui() -> void:
	_photo_book_panel = CanvasLayer.new()
	_photo_book_panel.layer = 15
	_photo_book_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_photo_book_panel.visible = false
	add_child(_photo_book_panel)

	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_FULL_RECT
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	_photo_book_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Photo Book"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): _toggle_photo_book())
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_photo_grid = GridContainer.new()
	_photo_grid.columns = 4
	scroll.add_child(_photo_grid)

func _populate_photo_grid() -> void:
	for child in _photo_grid.get_children():
		child.queue_free()
	for path in _photos:
		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(200, 150)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img:
				tex_rect.texture = ImageTexture.create_from_image(img)
		_photo_grid.add_child(tex_rect)
