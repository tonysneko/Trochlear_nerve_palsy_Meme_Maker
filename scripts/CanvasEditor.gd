extends Node2D

# 0: NONE, 1: SET_PUPIL_CENTER, 2: DRAW_EYE_MASK, 3: DRAW_MOVE_BOUNDS
var current_mode: int = 0
var active_template: EyeTemplate

func set_target_template(template: EyeTemplate, mode: int) -> void:
	active_template = template
	current_mode = mode
	queue_redraw()

func _input(event: InputEvent) -> void:
	if current_mode == 0 or not active_template:
		return
		
	# 左鍵點擊繪製，與右鍵拖拽相機分離
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos = get_local_mouse_position()
		
		match current_mode:
			1: # SET_PUPIL_CENTER
				active_template.pupil_center = local_pos
			2: # DRAW_EYE_MASK
				active_template.eye_mask_polygon.append(local_pos)
			3: # DRAW_MOVE_BOUNDS
				active_template.move_bounds_polygon.append(local_pos)
				
		var main_node = get_tree().current_scene
		if main_node and main_node.has_method("refresh_active_eye_node"):
			main_node.refresh_active_eye_node()
			
		queue_redraw()

func clear_current_points() -> void:
	if not active_template:
		return
		
	match current_mode:
		1:
			active_template.pupil_center = Vector2.ZERO
		2:
			active_template.eye_mask_polygon.clear()
		3:
			active_template.move_bounds_polygon.clear()
			
	queue_redraw()

func _draw() -> void:
	if not active_template or current_mode == 0:
		return
		
	# 獲取相機 Zoom 比例，動態計算以保證點線粗細不變
	var cam = get_viewport().get_camera_2d()
	var zoom_factor = cam.zoom.x if cam else 1.0
	
	var point_radius = 4.0 / zoom_factor
	var line_width = 2.0 / zoom_factor

	# 繪製瞳孔中心紅點
	if active_template.pupil_center != Vector2.ZERO:
		draw_circle(active_template.pupil_center, point_radius * 1.2, Color.RED)
		
	# 繪製眼眶多邊形綠線
	if active_template.eye_mask_polygon.size() > 0:
		for pt in active_template.eye_mask_polygon:
			draw_circle(pt, point_radius, Color.GREEN)
		if active_template.eye_mask_polygon.size() > 1:
			var pts = Array(active_template.eye_mask_polygon)
			pts.append(pts[0])
			draw_polyline(PackedVector2Array(pts), Color.GREEN, line_width)
			
	# 繪製活動範圍多邊形青色線
	if active_template.move_bounds_polygon.size() > 0:
		for pt in active_template.move_bounds_polygon:
			draw_circle(pt, point_radius, Color.CYAN)
		if active_template.move_bounds_polygon.size() > 1:
			var pts = Array(active_template.move_bounds_polygon)
			pts.append(pts[0])
			draw_polyline(PackedVector2Array(pts), Color.CYAN, line_width)
