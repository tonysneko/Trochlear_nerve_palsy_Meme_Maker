class_name Main
extends Control

enum EditMode { NONE, SET_PUPIL_CENTER, DRAW_EYE_MASK, DRAW_MOVE_BOUNDS }

# ----------------- @export 綁定區 -----------------
@export_group("畫布區節點")
@export var sub_viewport: SubViewport
@export var base_sprite: Sprite2D
@export var canvas_editor: Node2D
@export var eye_container: Node2D
@export var camera: Camera2D # 攝影機節點

@export_group("右側控制區節點")
@export var base_image_btn: Button
@export var pupil_image_btn: Button
@export var follower_image_btn: Button
@export var clear_follower_btn: Button
@export var rotate_follower_check: CheckBox # 同步物旋轉開關 CheckBox
@export var follower_speed_slider: HSlider # 同步物旋轉速度滑塊

@export var add_template_btn: Button
@export var remove_template_btn: Button
@export var mode_option: OptionButton
@export var clear_points_btn: Button
@export var move_type_option: OptionButton
@export var speed_slider: HSlider
@export var sync_check: CheckBox
@export var is_animated_check: CheckBox
@export var template_item_list: ItemList

@export_group("錄製與導出 AVI")
@export var record_avi_btn: Button
@export var avi_recorder: AviRecorder

@export_group("檔案選擇對話框")
@export var base_file_dialog: FileDialog
@export var pupil_file_dialog: FileDialog
@export var follower_file_dialog: FileDialog
@export var save_avi_dialog: FileDialog

@export_group("預設資源")
@export var eye_node_scene: PackedScene

# ----------------- 數據變數 -----------------
var templates: Array[EyeTemplate] = []
var selected_index: int = -1
var current_edit_mode: EditMode = EditMode.NONE

# 儲存玩家提前選擇好的 AVI 導出路徑
var target_export_path: String = ""

# ----------------- 相機控制變數 -----------------
var is_right_click_dragging: bool = false
var drag_start_mouse_pos: Vector2 = Vector2.ZERO
var drag_start_cam_pos: Vector2 = Vector2.ZERO

const MIN_ZOOM: float = 0.1
const MAX_ZOOM: float = 5.0
const ZOOM_STEP: float = 0.1

func _ready() -> void:
	setup_ui_options()
	connect_ui_signals()
	update_ui_state()
	init_camera()

func init_camera() -> void:
	if camera:
		camera.enabled = true
		camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		camera.zoom = Vector2.ONE

func setup_ui_options() -> void:
	if mode_option:
		mode_option.clear()
		mode_option.add_item("模式：正常預覽 (NONE)", EditMode.NONE)
		mode_option.add_item("模式：標記瞳孔中心", EditMode.SET_PUPIL_CENTER)
		mode_option.add_item("模式：劃定眼眶範圍 (遮罩)", EditMode.DRAW_EYE_MASK)
		mode_option.add_item("模式：劃定活動範圍", EditMode.DRAW_MOVE_BOUNDS)
		
	if move_type_option:
		move_type_option.clear()
		move_type_option.add_item("隨機平滑 (RANDOM_SMOOTH)", 0)
		move_type_option.add_item("圓週運動 (CIRCULAR)", 1)
		move_type_option.add_item("突然移動 (SUDDEN_JUMP)", 2)
		
	if speed_slider:
		speed_slider.min_value = 10.0
		speed_slider.max_value = 300.0
		speed_slider.value = 100.0

	if follower_speed_slider:
		follower_speed_slider.min_value = -10.0
		follower_speed_slider.max_value = 10.0
		follower_speed_slider.step = 0.5
		follower_speed_slider.value = 3.0

	if record_avi_btn:
		record_avi_btn.text = "開始錄製 (選擇路徑)"

func connect_ui_signals() -> void:
	base_image_btn.pressed.connect(_on_base_image_btn_pressed)
	pupil_image_btn.pressed.connect(_on_pupil_image_btn_pressed)
	
	if follower_image_btn:
		follower_image_btn.pressed.connect(_on_follower_image_btn_pressed)
	if clear_follower_btn:
		clear_follower_btn.pressed.connect(_on_clear_follower_btn_pressed)
	if rotate_follower_check:
		rotate_follower_check.toggled.connect(_on_rotate_follower_toggled)
	if follower_speed_slider:
		follower_speed_slider.value_changed.connect(_on_follower_speed_slider_value_changed)

	add_template_btn.pressed.connect(_on_add_template_btn_pressed)
	remove_template_btn.pressed.connect(_on_remove_template_btn_pressed)
	
	mode_option.item_selected.connect(_on_mode_option_selected)
	clear_points_btn.pressed.connect(_on_clear_points_btn_pressed)
	move_type_option.item_selected.connect(_on_move_type_option_selected)
	speed_slider.value_changed.connect(_on_speed_slider_value_changed)
	sync_check.toggled.connect(_on_sync_check_toggled)
	
	if is_animated_check:
		is_animated_check.toggled.connect(_on_is_animated_toggled)
	
	template_item_list.item_selected.connect(_on_template_selected)
	
	if base_file_dialog:
		base_file_dialog.file_selected.connect(_on_base_file_selected)
	if pupil_file_dialog:
		pupil_file_dialog.file_selected.connect(_on_pupil_file_selected)
	if follower_file_dialog:
		follower_file_dialog.file_selected.connect(_on_follower_file_selected)

	# ----------------- AVI 錄製信號綁定 -----------------
	if record_avi_btn:
		record_avi_btn.pressed.connect(_on_record_avi_btn_pressed)

	if save_avi_dialog:
		save_avi_dialog.file_selected.connect(_on_save_avi_file_selected)
		save_avi_dialog.filters = PackedStringArray(["*.avi ; AVI 影片檔"])

	if avi_recorder:
		# 【核心修復】：綁定錄製停止信號
		avi_recorder.recording_stopped.connect(_on_avi_recording_stopped)
		avi_recorder.export_finished.connect(_on_avi_export_finished)
		avi_recorder.export_failed.connect(_on_avi_export_failed)

# ----------------- 相機縮放與右鍵拖拽邏輯 -----------------
func _input(event: InputEvent) -> void:
	if not camera or not base_sprite or not base_sprite.texture:
		return

	# 1. 滾輪縮放
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(ZOOM_STEP)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-ZOOM_STEP)
				get_viewport().set_input_as_handled()
				
			# 2. 右鍵拖拽開始 / 結束
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				is_right_click_dragging = true
				drag_start_mouse_pos = event.global_position
				drag_start_cam_pos = camera.position
				get_viewport().set_input_as_handled()
		else:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				is_right_click_dragging = false

	# 3. 右鍵拖拽移動中
	elif event is InputEventMouseMotion and is_right_click_dragging:
		var mouse_delta = (event.global_position - drag_start_mouse_pos) / camera.zoom.x
		camera.position = drag_start_cam_pos - mouse_delta
		_clamp_camera_position()
		get_viewport().set_input_as_handled()

func _zoom_camera(amount: float) -> void:
	var factor = 1.15 if amount > 0 else (1.0 / 1.15)
	var new_zoom = clamp(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	
	camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera_position()
	
	if canvas_editor:
		canvas_editor.queue_redraw()
	for i in range(eye_container.get_child_count()):
		var eye_node = eye_container.get_child(i)
		if eye_node.debug_draw:
			eye_node.debug_draw.queue_redraw()

func _clamp_camera_position() -> void:
	if not camera or not base_sprite or not base_sprite.texture:
		return
		
	var viewport_size = sub_viewport.get_visible_rect().size if sub_viewport else get_viewport_rect().size
	var tex_size = base_sprite.texture.get_size() * base_sprite.scale
	var current_zoom = camera.zoom.x
	
	var visible_size = viewport_size / current_zoom
	var half_vis = visible_size / 2.0
	
	var min_x = half_vis.x
	var max_x = max(min_x, tex_size.x - half_vis.x)
	var min_y = half_vis.y
	var max_y = max(min_y, tex_size.y - half_vis.y)
	
	if tex_size.x <= visible_size.x:
		camera.position.x = tex_size.x / 2.0
	else:
		camera.position.x = clamp(camera.position.x, min_x, max_x)
		
	if tex_size.y <= visible_size.y:
		camera.position.y = tex_size.y / 2.0
	else:
		camera.position.y = clamp(camera.position.y, min_y, max_y)

# ----------------- UI 響應與邏輯 -----------------
func _on_add_template_btn_pressed() -> void:
	if templates.size() >= 10:
		return
		
	var new_temp = EyeTemplate.new()
	new_temp.name = "眼球模板 " + str(templates.size() + 1)
	templates.append(new_temp)
	
	if eye_node_scene:
		var node = eye_node_scene.instantiate()
		eye_container.add_child(node)
		node.setup(new_temp)
		
	refresh_template_list()
	select_template(templates.size() - 1)

func _on_remove_template_btn_pressed() -> void:
	if selected_index < 0 or selected_index >= templates.size():
		return
		
	templates.remove_at(selected_index)
	var child_to_remove = eye_container.get_child(selected_index)
	if child_to_remove:
		child_to_remove.queue_free()
		
	selected_index = -1
	refresh_template_list()
	update_ui_state()

func refresh_template_list() -> void:
	if not template_item_list:
		return
		
	template_item_list.clear()
	for i in range(templates.size()):
		var t = templates[i]
		var label_text = t.name
		if t.follower_texture:
			label_text += " [含同步物]"
			
		var item_index = template_item_list.add_item(label_text)
		template_item_list.set_item_metadata(item_index, i)

func select_template(idx: int) -> void:
	if idx < 0 or idx >= templates.size():
		selected_index = -1
		if template_item_list:
			template_item_list.deselect_all()
		update_ui_state()
		return

	selected_index = idx
	
	if template_item_list and template_item_list.get_item_count() > selected_index:
		template_item_list.select(selected_index)
	
	for i in range(eye_container.get_child_count()):
		var eye_node = eye_container.get_child(i)
		eye_node.is_selected = (i == selected_index)
		if eye_node.debug_draw:
			eye_node.debug_draw.queue_redraw()
		
	update_ui_state()

func _on_template_selected(idx: int) -> void:
	select_template(idx)

func update_ui_state() -> void:
	var has_selection = (selected_index >= 0 and selected_index < templates.size())
	pupil_image_btn.disabled = not has_selection
	
	if follower_image_btn:
		follower_image_btn.disabled = not has_selection
	if clear_follower_btn:
		var has_follower = has_selection and (templates[selected_index].follower_texture != null)
		clear_follower_btn.disabled = not has_follower
	if rotate_follower_check:
		rotate_follower_check.disabled = not has_selection
	if follower_speed_slider:
		follower_speed_slider.editable = has_selection

	mode_option.disabled = not has_selection
	clear_points_btn.disabled = not has_selection
	move_type_option.disabled = not has_selection
	speed_slider.editable = has_selection
	sync_check.disabled = not has_selection
	if is_animated_check:
		is_animated_check.disabled = not has_selection
	
	if has_selection:
		var cur = templates[selected_index]
		speed_slider.value = cur.speed
		sync_check.button_pressed = cur.is_synchronized
		if is_animated_check:
			is_animated_check.button_pressed = cur.is_animated
		if rotate_follower_check:
			rotate_follower_check.button_pressed = cur.is_follower_rotating
		if follower_speed_slider:
			follower_speed_slider.value = cur.follower_rotate_speed
		
		match cur.move_type:
			"RANDOM_SMOOTH":
				move_type_option.select(0)
			"CIRCULAR":
				move_type_option.select(1)
			"SUDDEN_JUMP":
				move_type_option.select(2)
			_:
				move_type_option.select(0)
			
		canvas_editor.set_target_template(cur, current_edit_mode)

func _on_mode_option_selected(idx: int) -> void:
	current_edit_mode = idx as EditMode
	
	for i in range(eye_container.get_child_count()):
		var eye_node = eye_container.get_child(i)
		eye_node.current_edit_mode = current_edit_mode
		
	if selected_index >= 0 and selected_index < templates.size():
		canvas_editor.set_target_template(templates[selected_index], current_edit_mode)

func _on_clear_points_btn_pressed() -> void:
	canvas_editor.clear_current_points()
	refresh_active_eye_node()

func _on_move_type_option_selected(idx: int) -> void:
	if selected_index < 0: return
	match idx:
		0:
			templates[selected_index].move_type = "RANDOM_SMOOTH"
		1:
			templates[selected_index].move_type = "CIRCULAR"
		2:
			templates[selected_index].move_type = "SUDDEN_JUMP"

func _on_speed_slider_value_changed(val: float) -> void:
	if selected_index < 0: return
	templates[selected_index].speed = val

func _on_sync_check_toggled(toggled: bool) -> void:
	if selected_index < 0: return
	templates[selected_index].is_synchronized = toggled

func _on_is_animated_toggled(toggled: bool) -> void:
	if selected_index < 0: return
	templates[selected_index].is_animated = toggled

func _on_rotate_follower_toggled(toggled: bool) -> void:
	if selected_index < 0: return
	templates[selected_index].is_follower_rotating = toggled

func _on_follower_speed_slider_value_changed(val: float) -> void:
	if selected_index < 0: return
	templates[selected_index].follower_rotate_speed = val

func refresh_active_eye_node() -> void:
	if selected_index >= 0 and selected_index < eye_container.get_child_count():
		var eye_node = eye_container.get_child(selected_index)
		eye_node.update_visuals()

# ----------------- 新版 AVI 錄製與導出邏輯 -----------------
func _on_record_avi_btn_pressed() -> void:
	if not avi_recorder:
		push_error("未指定 AviRecorder 節點！")
		return

	# 1. 當前不在錄製中：點擊後先彈出 FileDialog 讓玩家選擇儲存位置
	if not avi_recorder.is_recording:
		if save_avi_dialog:
			save_avi_dialog.popup_centered_ratio(0.7)
	# 2. 當前正在錄製中：手動點擊按鈕停止錄製
	else:
		avi_recorder.stop_recording_meme(eye_container, sub_viewport)

func _on_save_avi_file_selected(path: String) -> void:
	# 玩家選好路徑後保存檔名，並自動開始錄製
	target_export_path = path

	if mode_option:
		mode_option.select(EditMode.NONE)
		_on_mode_option_selected(EditMode.NONE)

	avi_recorder.start_recording_meme(base_sprite, eye_container, 60)
	
	if record_avi_btn:
		record_avi_btn.text = "停止錄製 (錄製中...)"

# 【核心修復】：無論是手動按停止按鈕，還是 30 秒滿自動停止，都會觸發這個函式
func _on_avi_recording_stopped() -> void:
	if record_avi_btn:
		record_avi_btn.text = "AVI 導出中，請稍候..."
		record_avi_btn.disabled = true
	
	# 自動開始多線程導出保存
	if avi_recorder and target_export_path != "":
		avi_recorder.stop_and_export(target_export_path)

func _on_avi_export_finished(output_path: String) -> void:
	if record_avi_btn:
		record_avi_btn.disabled = false
		record_avi_btn.text = "開始錄製 (選擇路徑)"
	print("AVI 影片導出成功！檔案位於：", output_path)

func _on_avi_export_failed(reason: String) -> void:
	if record_avi_btn:
		record_avi_btn.disabled = false
		record_avi_btn.text = "開始錄製 (選擇路徑)"
	push_error("AVI 導出失敗：" + reason)

# ----------------- 圖片上傳邏輯 -----------------
func _on_base_image_btn_pressed() -> void:
	if base_file_dialog:
		base_file_dialog.popup_centered_ratio(0.7)

func _on_base_file_selected(path: String) -> void:
	var img = Image.load_from_file(path)
	if img:
		var tex = ImageTexture.create_from_image(img)
		base_sprite.texture = tex
		base_sprite.centered = true
		
		var img_size = tex.get_size()

		if sub_viewport:
			var viewport_container = sub_viewport.get_parent() as SubViewportContainer
			if viewport_container:
				viewport_container.stretch = true

		base_sprite.position = img_size / 2.0
		
		if camera:
			camera.position = img_size / 2.0
			_clamp_camera_position()

func _on_pupil_image_btn_pressed() -> void:
	if selected_index < 0: return
	if pupil_file_dialog:
		pupil_file_dialog.popup_centered_ratio(0.7)

func _on_pupil_file_selected(path: String) -> void:
	if selected_index >= 0:
		var img = Image.load_from_file(path)
		if img:
			var tex = ImageTexture.create_from_image(img)
			templates[selected_index].pupil_texture = tex
			refresh_active_eye_node()

func _on_follower_image_btn_pressed() -> void:
	if selected_index < 0: return
	if follower_file_dialog:
		follower_file_dialog.popup_centered_ratio(0.7)

func _on_follower_file_selected(path: String) -> void:
	if selected_index >= 0 and selected_index < templates.size():
		var img = Image.load_from_file(path)
		if img:
			var tex = ImageTexture.create_from_image(img)
			templates[selected_index].follower_texture = tex
			refresh_active_eye_node()
			refresh_template_list()
			update_ui_state()

func _on_clear_follower_btn_pressed() -> void:
	if selected_index >= 0 and selected_index < templates.size():
		templates[selected_index].follower_texture = null
		refresh_active_eye_node()
		refresh_template_list()
		update_ui_state()
