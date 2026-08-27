class_name AviRecorder
extends Node

signal recording_started
signal recording_stopped # 【新增】：錄製停止信號（包含手動停止與 30 秒自動停止）
signal export_finished(output_path: String)
signal export_failed(reason: String)

var is_recording: bool = false
var target_fps: int = 60
var frame_time_accumulator: float = 0.0
var frame_interval: float = 1.0 / 60.0

# 錄製時間限制（秒）
@export var max_recording_duration: float = 30.0
var total_recorded_time: float = 0.0

var recording_jpeg_quality: float = 0.85
@export var render_scale: float = 0.75

var record_viewport: SubViewport
var export_size := Vector2i.ZERO

# 記錄所有產生的臨時圖片檔案路徑
var temp_frame_paths: Array[String] = []
var temp_dir_path: String = "user://temp_recording_frames/"
var frame_counter: int = 0

# 多線程寫入硬碟與 JPEG 壓縮
var worker_thread: Thread
var queue_mutex: Mutex
var queue_semaphore: Semaphore
var write_queue: Array[Dictionary] = [] # 包含 { "path": String, "image": Image }
var exit_thread_flag: bool = false

# 保存 EyeContainer 參照以便自動停止時歸位
var _current_eye_container: Node2D = null
var _current_original_parent: Node = null

func _ready() -> void:
	queue_mutex = Mutex.new()
	queue_semaphore = Semaphore.new()
	worker_thread = Thread.new()
	worker_thread.start(_disk_writer_loop)
	_setup_record_viewport()

func _setup_record_viewport() -> void:
	record_viewport = SubViewport.new()
	record_viewport.name = "RecordSubViewport"
	record_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	record_viewport.transparent_bg = false
	add_child(record_viewport)

func _exit_tree() -> void:
	_stop_worker_thread()

func _stop_worker_thread() -> void:
	if worker_thread and worker_thread.is_started():
		queue_mutex.lock()
		exit_thread_flag = true
		queue_mutex.unlock()
		queue_semaphore.post()
		worker_thread.wait_to_finish()

func _process(delta: float) -> void:
	if not is_recording:
		return

	# 累加總錄製時間
	total_recorded_time += delta

	# 達到 30 秒上限自動停止錄製
	if total_recorded_time >= max_recording_duration:
		print("已達到最高錄製時間限制 (%.1f 秒)，自動停止錄製。" % max_recording_duration)
		stop_recording_meme(_current_eye_container, _current_original_parent)
		return

	frame_time_accumulator += delta
	if frame_time_accumulator >= frame_interval:
		frame_time_accumulator -= frame_interval
		_capture_frame()

func start_recording_meme(base_sprite: Sprite2D, eye_container: Node2D, fps: int = 60) -> void:
	if not base_sprite or not base_sprite.texture:
		push_error("無底圖，無法錄製！")
		return

	target_fps = fps
	frame_interval = 1.0 / float(fps)
	frame_time_accumulator = 0.0
	total_recorded_time = 0.0
	frame_counter = 0

	# 暫存節點指標，供自動停止時回原位使用
	_current_eye_container = eye_container
	if eye_container:
		_current_original_parent = eye_container.get_parent()

	# 建立硬碟臨時資料夾
	var dir := DirAccess.open("user://")
	if dir:
		if dir.dir_exists("temp_recording_frames"):
			_clear_temp_folder()
		dir.make_dir("temp_recording_frames")

	temp_frame_paths.clear()

	var orig_size = Vector2i(base_sprite.texture.get_size())
	export_size = Vector2i(
		int(orig_size.x * render_scale) & ~1,
		int(orig_size.y * render_scale) & ~1
	)

	record_viewport.size = export_size

	for child in record_viewport.get_children():
		child.queue_free()

	var record_root = Node2D.new()
	record_viewport.add_child(record_root)
	record_root.scale = Vector2(render_scale, render_scale)

	var bg_copy = Sprite2D.new()
	bg_copy.texture = base_sprite.texture
	bg_copy.centered = true
	bg_copy.position = Vector2(orig_size) / 2.0
	record_root.add_child(bg_copy)

	if eye_container:
		eye_container.get_parent().remove_child(eye_container)
		record_root.add_child(eye_container)
		eye_container.position = Vector2.ZERO

	is_recording = true
	recording_started.emit()

func stop_recording_meme(eye_container: Node2D = null, original_parent: Node = null) -> void:
	if not is_recording:
		return
		
	is_recording = false

	var target_eye = eye_container if eye_container else _current_eye_container
	var target_parent = original_parent if original_parent else _current_original_parent

	if target_eye and target_parent and is_instance_valid(target_eye) and is_instance_valid(target_parent):
		if target_eye.get_parent():
			target_eye.get_parent().remove_child(target_eye)
		target_parent.add_child(target_eye)

	_current_eye_container = null
	_current_original_parent = null

	# 【核心修復】：發送錄製停止信號，通知 Main.gd 開始進行導出與更新按鈕狀態
	call_deferred("emit_signal", "recording_stopped")

func stop_and_export(output_path: String) -> void:
	if is_recording:
		stop_recording_meme()

	var export_thread := Thread.new()
	export_thread.start(_thread_export_task.bind(output_path))

func _capture_frame() -> void:
	if record_viewport:
		var img := record_viewport.get_texture().get_image()
		if img:
			frame_counter += 1
			var file_name := "frame_%06d.jpg" % frame_counter
			var full_path := temp_dir_path + file_name
			
			temp_frame_paths.append(full_path)
			
			queue_mutex.lock()
			write_queue.append({ "path": full_path, "image": img })
			queue_mutex.unlock()
			queue_semaphore.post()

# 硬碟寫入與 JPEG 轉碼背景線程
func _disk_writer_loop() -> void:
	while true:
		queue_semaphore.wait()

		queue_mutex.lock()
		if exit_thread_flag:
			queue_mutex.unlock()
			break

		var task: Dictionary = {}
		if not write_queue.is_empty():
			task = write_queue.pop_front()
		queue_mutex.unlock()

		if not task.is_empty():
			var img: Image = task["image"]
			var path: String = task["path"]
			
			var jpg_bytes := img.save_jpg_to_buffer(recording_jpeg_quality)
			
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_buffer(jpg_bytes)
				file.close()

func _thread_export_task(output_path: String) -> void:
	# 等待所有佇列中的臨時畫面在背景轉碼並寫入硬碟完畢
	while true:
		queue_mutex.lock()
		var remaining := write_queue.size()
		queue_mutex.unlock()
		if remaining == 0:
			break
		OS.delay_msec(10)

	if temp_frame_paths.is_empty():
		call_deferred("_emit_failed", "沒有抓取到任何畫面。")
		return

	# 從硬碟逐幀讀取數據並寫入最終 AVI 檔案
	var success := AviExporter.export_avi_from_disk_files(
		temp_frame_paths, 
		output_path, 
		export_size.x, 
		export_size.y, 
		target_fps
	)

	# 導出完成後，清理硬碟中的臨時圖片
	_clear_temp_folder()

	if success:
		call_deferred("_emit_success", output_path)
	else:
		call_deferred("_emit_failed", "AVI 寫入失敗。")

func _clear_temp_folder() -> void:
	var dir := DirAccess.open(temp_dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

func _emit_success(path: String) -> void:
	export_finished.emit(path)

func _emit_failed(reason: String) -> void:
	export_failed.emit(reason)
