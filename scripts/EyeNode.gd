class_name EyeNode
extends Node2D

@onready var mask_node: Polygon2D = $EyeMaskNode
@onready var pupil_sprite: Sprite2D = $EyeMaskNode/PupilSprite
@onready var debug_draw: Node2D = $DebugDraw

# 同步物 Sprite (改為 EyeNode 的直接子節點，避開遮罩剪裁)
var follower_sprite: Sprite2D

var template_data: EyeTemplate

# 0: NONE, 1: SET_PUPIL_CENTER, 2: DRAW_EYE_MASK, 3: DRAW_MOVE_BOUNDS
var current_edit_mode: int = 0
var is_selected: bool = false

# --- 隨機平滑 / 圓週運動變數 ---
var random_target_pos: Vector2 = Vector2.ZERO
var circular_angle: float = 0.0

# --- 突然移動 (SUDDEN_JUMP) 專屬變數 ---
enum SuddenState { PAUSE, DASH }
var sudden_state: SuddenState = SuddenState.PAUSE
var sudden_timer: float = 0.0
var sudden_target_pos: Vector2 = Vector2.ZERO
var sudden_current_velocity: Vector2 = Vector2.ZERO

# 同步物自轉角度
var follower_rotation_angle: float = 0.0

func _ready() -> void:
	if debug_draw and not debug_draw.is_connected("draw", Callable(self, "_on_debug_draw_draw")):
		debug_draw.draw.connect(_on_debug_draw_draw)
	
	_setup_follower_sprite()

func _setup_follower_sprite() -> void:
	if not follower_sprite:
		follower_sprite = Sprite2D.new()
		follower_sprite.name = "FollowerSprite"
		follower_sprite.centered = true
		# 掛在 EyeNode 下，避開遮罩剪裁
		add_child(follower_sprite)

func setup(data: EyeTemplate) -> void:
	template_data = data
	update_visuals()
	reset_motion_state()

func reset_motion_state() -> void:
	if template_data:
		pupil_sprite.position = template_data.pupil_center
		random_target_pos = template_data.pupil_center
		circular_angle = 0.0
		follower_rotation_angle = 0.0
		
		# 重置突然移動狀態
		sudden_state = SuddenState.PAUSE
		sudden_timer = randf_range(0.2, 0.8)
		sudden_target_pos = template_data.pupil_center
		sudden_current_velocity = Vector2.ZERO
		
		if follower_sprite:
			follower_sprite.rotation = 0.0
			follower_sprite.position = template_data.pupil_center

func update_visuals() -> void:
	if not template_data:
		return
		
	mask_node.polygon = template_data.eye_mask_polygon
	mask_node.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	
	if template_data.pupil_texture:
		pupil_sprite.texture = template_data.pupil_texture
		pupil_sprite.centered = true
	else:
		pupil_sprite.texture = null

	# 更新同步物貼圖與可見度
	_setup_follower_sprite()
	if follower_sprite:
		if template_data.follower_texture:
			follower_sprite.texture = template_data.follower_texture
			follower_sprite.visible = true
			follower_sprite.position = pupil_sprite.position
		else:
			follower_sprite.texture = null
			follower_sprite.visible = false
	
	if debug_draw:
		debug_draw.queue_redraw()

func _process(delta: float) -> void:
	if not template_data:
		return
		
	if current_edit_mode == 0 and template_data.is_animated:
		calculate_pupil_position(delta)
	else:
		pupil_sprite.position = template_data.pupil_center

	# 手動對齊同步物位置
	_sync_follower_transform(delta)

func _sync_follower_transform(delta: float) -> void:
	if follower_sprite and follower_sprite.visible and template_data:
		follower_sprite.position = pupil_sprite.position
		
		if template_data.is_follower_rotating:
			var rot_speed = template_data.follower_rotate_speed
			follower_rotation_angle += delta * rot_speed
			follower_sprite.rotation = follower_rotation_angle
		else:
			follower_sprite.rotation = 0.0

func calculate_pupil_position(delta: float) -> void:
	var is_sync_active = template_data.is_synchronized and get_index() > 0
	
	if is_sync_active:
		var has_valid_center = template_data.pupil_center != Vector2.ZERO
		var has_valid_mask = template_data.eye_mask_polygon.size() >= 3
		
		if not (has_valid_center and has_valid_mask):
			pupil_sprite.position = template_data.pupil_center
			return

		var master_node = get_parent().get_child(0) as EyeNode
		if master_node and master_node.template_data:
			_process_synchronized_motion(delta, master_node)
			return

	match template_data.move_type:
		"RANDOM_SMOOTH":
			_process_random_smooth_motion(delta, template_data, self)
		"CIRCULAR":
			_process_circular_motion(delta, template_data, self)
		"SUDDEN_JUMP":
			_process_sudden_jump_motion(delta, template_data, self)

func _process_synchronized_motion(delta: float, master: EyeNode) -> void:
	var master_temp = master.template_data
	
	match master_temp.move_type:
		"CIRCULAR":
			var master_params = master.get_circular_parameters()
			var my_center = template_data.pupil_center
			pupil_sprite.position = Vector2(
				my_center.x + cos(master.circular_angle) * master_params.rx,
				my_center.y + sin(master.circular_angle) * master_params.ry
			)
			
		"RANDOM_SMOOTH", "SUDDEN_JUMP":
			var master_offset = master.pupil_sprite.position - master_temp.pupil_center
			pupil_sprite.position = template_data.pupil_center + master_offset

func _process_random_smooth_motion(delta: float, data: EyeTemplate, node_ref: EyeNode) -> void:
	if node_ref.pupil_sprite.position.distance_to(node_ref.random_target_pos) < 2.0 or node_ref.random_target_pos == Vector2.ZERO:
		node_ref.random_target_pos = _generate_random_point_in_bounds(data)
	
	var move_speed = data.speed
	node_ref.pupil_sprite.position = node_ref.pupil_sprite.position.move_toward(node_ref.random_target_pos, move_speed * delta)

# --- 突然移動運動邏輯 ---
func _process_sudden_jump_motion(delta: float, data: EyeTemplate, node_ref: EyeNode) -> void:
	match node_ref.sudden_state:
		SuddenState.PAUSE:
			node_ref.sudden_current_velocity = Vector2.ZERO
			node_ref.sudden_timer -= delta
			
			if node_ref.sudden_timer <= 0.0:
				node_ref.sudden_target_pos = _generate_random_point_in_bounds(data)
				node_ref.sudden_state = SuddenState.DASH
				
		SuddenState.DASH:
			var current_pos = node_ref.pupil_sprite.position
			var dir = (node_ref.sudden_target_pos - current_pos).normalized()
			
			# 速度滑塊數值作為加速度
			var accel = data.speed * 15.0 
			node_ref.sudden_current_velocity += dir * accel * delta
			
			var next_pos = current_pos + node_ref.sudden_current_velocity * delta
			
			# 檢查是否超出邊界
			var polygon_to_use: PackedVector2Array = PackedVector2Array()
			if data.move_bounds_polygon.size() >= 3:
				polygon_to_use = data.move_bounds_polygon
			elif data.eye_mask_polygon.size() >= 3:
				polygon_to_use = data.eye_mask_polygon
				
			var hit_boundary = false
			if polygon_to_use.size() >= 3:
				if not Geometry2D.is_point_in_polygon(next_pos, polygon_to_use):
					hit_boundary = true
			
			# 接近目標點或撞擊邊界時停止衝刺，切換回停頓狀態
			if current_pos.distance_to(node_ref.sudden_target_pos) < 5.0 or hit_boundary:
				node_ref.sudden_state = SuddenState.PAUSE
				node_ref.sudden_timer = randf_range(0.2, 1.0)
				node_ref.sudden_current_velocity = Vector2.ZERO
			else:
				node_ref.pupil_sprite.position = next_pos

func _generate_random_point_in_bounds(data: EyeTemplate) -> Vector2:
	var polygon_to_use: PackedVector2Array = PackedVector2Array()
	if data.move_bounds_polygon.size() >= 3:
		polygon_to_use = data.move_bounds_polygon
	elif data.eye_mask_polygon.size() >= 3:
		polygon_to_use = data.eye_mask_polygon

	if polygon_to_use.size() < 3:
		var center = data.pupil_center if data.pupil_center != Vector2.ZERO else Vector2.ZERO
		return center + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		
	var rect = _get_polygon_bounding_box(polygon_to_use)
	for i in range(50):
		var candidate = Vector2(
			randf_range(rect.position.x, rect.end.x),
			randf_range(rect.position.y, rect.end.y)
		)
		if Geometry2D.is_point_in_polygon(candidate, polygon_to_use):
			return candidate
			
	return rect.get_center()

func _process_circular_motion(delta: float, data: EyeTemplate, node_ref: EyeNode) -> void:
	var params = node_ref.get_circular_parameters()
	node_ref.circular_angle += delta * (data.speed / 20.0)

	node_ref.pupil_sprite.position = Vector2(
		params.center.x + cos(node_ref.circular_angle) * params.rx,
		params.center.y + sin(node_ref.circular_angle) * params.ry
	)

func get_circular_parameters() -> Dictionary:
	var polygon_to_use: PackedVector2Array = PackedVector2Array()
	if template_data.move_bounds_polygon.size() >= 3:
		polygon_to_use = template_data.move_bounds_polygon
	elif template_data.eye_mask_polygon.size() >= 3:
		polygon_to_use = template_data.eye_mask_polygon

	var center: Vector2
	var rx: float
	var ry: float

	if polygon_to_use.size() >= 3:
		var rect = _get_polygon_bounding_box(polygon_to_use)
		center = rect.get_center()
		rx = rect.size.x / 2.0
		ry = rect.size.y / 2.0
	else:
		center = template_data.pupil_center if template_data.pupil_center != Vector2.ZERO else Vector2.ZERO
		rx = 30.0
		ry = 30.0
		
	return {"center": center, "rx": rx, "ry": ry}

func _get_polygon_bounding_box(polygon: PackedVector2Array) -> Rect2:
	if polygon.size() == 0:
		return Rect2()
		
	var min_x = polygon[0].x
	var min_y = polygon[0].y
	var max_x = polygon[0].x
	var max_y = polygon[0].y
	
	for pt in polygon:
		min_x = min(min_x, pt.x)
		min_y = min(min_y, pt.y)
		max_x = max(max_x, pt.x)
		max_y = max(max_y, pt.y)
		
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _on_debug_draw_draw() -> void:
	if not is_selected or not template_data or current_edit_mode == 0:
		return
		
	var cam = get_viewport().get_camera_2d()
	var zoom_factor = cam.zoom.x if cam else 1.0
	var point_radius = 4.0 / zoom_factor
	var line_width = 2.0 / zoom_factor
		
	if template_data.pupil_center != Vector2.ZERO:
		debug_draw.draw_circle(template_data.pupil_center, point_radius * 1.2, Color.RED)
		
	if template_data.eye_mask_polygon.size() > 1:
		var pts = Array(template_data.eye_mask_polygon)
		pts.append(pts[0])
		debug_draw.draw_polyline(PackedVector2Array(pts), Color.GREEN, line_width)
		
	if template_data.move_bounds_polygon.size() > 1:
		var pts = Array(template_data.move_bounds_polygon)
		pts.append(pts[0])
		debug_draw.draw_polyline(PackedVector2Array(pts), Color.CYAN, line_width)
