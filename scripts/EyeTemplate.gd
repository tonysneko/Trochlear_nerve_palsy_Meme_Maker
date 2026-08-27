class_name EyeTemplate
extends Resource

@export var name: String = ""
@export var pupil_texture: Texture2D
@export var follower_texture: Texture2D # 同步物貼圖

# 【新增】同步物旋轉控制屬性
@export var is_follower_rotating: bool = false
@export var follower_rotate_speed: float = 3.0 # 弧度/秒 (約 180度/秒)

@export var pupil_center: Vector2 = Vector2.ZERO
@export var eye_mask_polygon: PackedVector2Array = PackedVector2Array()
@export var move_bounds_polygon: PackedVector2Array = PackedVector2Array()

@export var move_type: String = "RANDOM_SMOOTH"
@export var speed: float = 100.0
@export var is_synchronized: bool = false
@export var is_animated: bool = false
