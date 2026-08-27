class_name AviExporter
extends RefCounted

## 從硬碟流式讀取 JPEG 檔並合成 AVI 視頻
static func export_avi_from_disk_files(jpg_paths: Array[String], output_path: String, width: int, height: int, fps: int = 60) -> bool:
	if jpg_paths.is_empty():
		push_error("沒有可導出的畫面檔案。")
		return false

	var frame_count := jpg_paths.size()

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		push_error("無法開啟檔案寫入：" + output_path)
		return false

	# 1. 構建 AVI Headers
	var strh_data := PackedByteArray()
	strh_data.append_array("vids".to_ascii_buffer())
	strh_data.append_array("MJPG".to_ascii_buffer())
	strh_data.append_array(_int32_to_bytes(0))
	strh_data.append_array(_int16_to_bytes(0))
	strh_data.append_array(_int16_to_bytes(0))
	strh_data.append_array(_int32_to_bytes(0))
	strh_data.append_array(_int32_to_bytes(1))
	strh_data.append_array(_int32_to_bytes(fps))
	strh_data.append_array(_int32_to_bytes(0))
	strh_data.append_array(_int32_to_bytes(frame_count))
	strh_data.append_array(_int32_to_bytes(width * height * 3))
	strh_data.append_array(_int32_to_bytes(10000))
	strh_data.append_array(_int32_to_bytes(0))
	strh_data.append_array(_int16_to_bytes(0))
	strh_data.append_array(_int16_to_bytes(0))
	strh_data.append_array(_int16_to_bytes(width))
	strh_data.append_array(_int16_to_bytes(height))

	var strh_chunk := PackedByteArray()
	strh_chunk.append_array("strh".to_ascii_buffer())
	strh_chunk.append_array(_int32_to_bytes(strh_data.size()))
	strh_chunk.append_array(strh_data)

	var strf_data := PackedByteArray()
	strf_data.append_array(_int32_to_bytes(40))
	strf_data.append_array(_int32_to_bytes(width))
	strf_data.append_array(_int32_to_bytes(height))
	strf_data.append_array(_int16_to_bytes(1))
	strf_data.append_array(_int16_to_bytes(24))
	strf_data.append_array("MJPG".to_ascii_buffer())
	strf_data.append_array(_int32_to_bytes(width * height * 3))
	strf_data.append_array(_int32_to_bytes(0))
	strf_data.append_array(_int32_to_bytes(0))
	strf_data.append_array(_int32_to_bytes(0))
	strf_data.append_array(_int32_to_bytes(0))

	var strf_chunk := PackedByteArray()
	strf_chunk.append_array("strf".to_ascii_buffer())
	strf_chunk.append_array(_int32_to_bytes(strf_data.size()))
	strf_chunk.append_array(strf_data)

	var strl_payload := PackedByteArray()
	strl_payload.append_array("strl".to_ascii_buffer())
	strl_payload.append_array(strh_chunk)
	strl_payload.append_array(strf_chunk)

	var strl_list := PackedByteArray()
	strl_list.append_array("LIST".to_ascii_buffer())
	strl_list.append_array(_int32_to_bytes(strl_payload.size()))
	strl_list.append_array(strl_payload)

	var micro_sec_per_frame := int(1000000.0 / float(fps))
	var avih_data := PackedByteArray()
	avih_data.append_array(_int32_to_bytes(micro_sec_per_frame))
	avih_data.append_array(_int32_to_bytes(width * height * 3 * fps))
	avih_data.append_array(_int32_to_bytes(0))
	avih_data.append_array(_int32_to_bytes(0x10))
	avih_data.append_array(_int32_to_bytes(frame_count))
	avih_data.append_array(_int32_to_bytes(0))
	avih_data.append_array(_int32_to_bytes(1))
	avih_data.append_array(_int32_to_bytes(width * height * 3))
	avih_data.append_array(_int32_to_bytes(width))
	avih_data.append_array(_int32_to_bytes(height))
	avih_data.append_array(_int32_to_bytes(0))
	avih_data.append_array(_int32_to_bytes(0))
	avih_data.append_array(_int32_to_bytes(0))
	avih_data.append_array(_int32_to_bytes(0))

	var avih_chunk := PackedByteArray()
	avih_chunk.append_array("avih".to_ascii_buffer())
	avih_chunk.append_array(_int32_to_bytes(avih_data.size()))
	avih_chunk.append_array(avih_data)

	var hdrl_payload := PackedByteArray()
	hdrl_payload.append_array("hdrl".to_ascii_buffer())
	hdrl_payload.append_array(avih_chunk)
	hdrl_payload.append_array(strl_list)

	var hdrl_list := PackedByteArray()
	hdrl_list.append_array("LIST".to_ascii_buffer())
	hdrl_list.append_array(_int32_to_bytes(hdrl_payload.size()))
	hdrl_list.append_array(hdrl_payload)

	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_buffer(_int32_to_bytes(0))
	file.store_buffer("AVI ".to_ascii_buffer())
	file.store_buffer(hdrl_list)

	var movi_list_start_pos := file.get_position()
	file.store_buffer("LIST".to_ascii_buffer())
	file.store_buffer(_int32_to_bytes(0))
	file.store_buffer("movi".to_ascii_buffer())

	# 2. 逐幀從硬碟讀取圖片並寫入 AVI
	var frame_offsets: Array[int] = []
	var frame_sizes: Array[int] = []
	var current_movi_offset := 4

	for path in jpg_paths:
		var img_file := FileAccess.open(path, FileAccess.READ)
		if not img_file:
			continue
		var jpg_bytes := img_file.get_buffer(img_file.get_length())
		img_file.close()

		var raw_size := jpg_bytes.size()
		var needs_padding := (raw_size % 2 != 0)
		var payload_size := raw_size + (1 if needs_padding else 0)

		frame_offsets.append(current_movi_offset)
		frame_sizes.append(payload_size)

		file.store_buffer("00dc".to_ascii_buffer())
		file.store_buffer(_int32_to_bytes(raw_size))
		file.store_buffer(jpg_bytes)

		if needs_padding:
			file.store_8(0)

		current_movi_offset += 8 + payload_size

	var movi_list_end_pos := file.get_position()
	var movi_payload_size := movi_list_end_pos - movi_list_start_pos - 8

	# 3. 寫入 Index Chunk (idx1)
	file.store_buffer("idx1".to_ascii_buffer())
	file.store_buffer(_int32_to_bytes(frame_count * 16))

	for i in range(frame_count):
		file.store_buffer("00dc".to_ascii_buffer())
		file.store_buffer(_int32_to_bytes(0x10))
		file.store_buffer(_int32_to_bytes(frame_offsets[i]))
		file.store_buffer(_int32_to_bytes(frame_sizes[i]))

	var total_file_size := file.get_position()

	file.seek(4)
	file.store_buffer(_int32_to_bytes(total_file_size - 8))

	file.seek(movi_list_start_pos + 4)
	file.store_buffer(_int32_to_bytes(movi_payload_size))

	file.close()
	return true

static func _int16_to_bytes(val: int) -> PackedByteArray:
	var arr := PackedByteArray()
	arr.resize(2)
	arr.encode_s16(0, val)
	return arr

static func _int32_to_bytes(val: int) -> PackedByteArray:
	var arr := PackedByteArray()
	arr.resize(4)
	arr.encode_s32(0, val)
	return arr
