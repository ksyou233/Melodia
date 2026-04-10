extends Node3D

## 作用：提供 2.5D 地图视角控制（平移、旋转、缩放），便于人工与脚本联调。
## 使用方法：挂载到 CameraRig 节点；默认使用 ui_ 系列输入和鼠标滚轮。
## 输入：键盘方向键/WASD 平移、鼠标滚轮缩放。
## 输出：更新 CameraRig 变换与 Camera3D 正交尺寸。
class_name MapCameraRig25D

@export var move_speed: float = 12.0
@export var zoom_step: float = 1.8
@export var min_zoom_size: float = 10.0
@export var max_zoom_size: float = 45.0
@export var initial_height: float = 18.0
@export var initial_horizontal_offset: float = 16.0
@export var initial_depth_offset: float = 16.0

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	_snap_to_default_view()


## 作用：按帧处理视角平移与旋转，确保地图浏览体验稳定。
## 使用方法：引擎自动调用。
## 输入：delta（帧间隔秒数）和输入状态。
## 输出：无。
func _process(delta: float) -> void:
	_handle_move(delta)


## 作用：处理鼠标滚轮缩放，便于快速检查不同地图区域。
## 使用方法：引擎自动调用。
## 输入：InputEvent。
## 输出：无。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(camera.size - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(camera.size + zoom_step)


## 作用：读取输入并在地图平面上平移相机支架。
## 使用方法：仅供 _process 内部调用。
## 输入：delta 与输入状态。
## 输出：无。
func _handle_move(delta: float) -> void:
	var input_vec: Vector2 = _get_move_input()
	var input_x: float = input_vec.x
	var input_z: float = input_vec.y

	var move_dir := Vector3(input_x, 0.0, input_z)
	if move_dir.length_squared() == 0.0:
		return

	move_dir = move_dir.normalized()
	var planar_x := Vector3(global_basis.x.x, 0.0, global_basis.x.z).normalized()
	var planar_z := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
	var global_move := (planar_x * move_dir.x) + (planar_z * move_dir.z)
	global_position += global_move * move_speed * delta


## 作用：统一读取平移输入，兼容 InputMap 与物理键位，确保 WASD 始终可用。
## 使用方法：仅供 _handle_move 内部调用。
## 输入：无。
## 输出：二维输入向量（x 为左右，y 为前后）。
func _get_move_input() -> Vector2:
	var left: float = Input.get_action_strength("ui_left")
	var right: float = Input.get_action_strength("ui_right")
	var up: float = Input.get_action_strength("ui_up")
	var down: float = Input.get_action_strength("ui_down")

	if Input.is_physical_key_pressed(KEY_A):
		left = 1.0
	if Input.is_physical_key_pressed(KEY_D):
		right = 1.0
	if Input.is_physical_key_pressed(KEY_W):
		up = 1.0
	if Input.is_physical_key_pressed(KEY_S):
		down = 1.0

	return Vector2(right - left, down - up)

## 作用：限制缩放范围，避免镜头过近或过远影响测试观察。
## 使用方法：仅供缩放逻辑调用。
## 输入：目标缩放值。
## 输出：无。
func _set_zoom(target_size: float) -> void:
	camera.size = clampf(target_size, min_zoom_size, max_zoom_size)


## 作用：将相机放置到固定 2.5D 视角并对准地图中心，避免启动时视野丢失。
## 使用方法：在 _ready 阶段自动调用，也可在调试时手动调用重置视角。
## 输入：无。
## 输出：无。
func _snap_to_default_view() -> void:
	var center: Vector3 = Vector3.ZERO
	var map_root: Node = get_parent()
	if map_root != null and map_root.has_method("get_map_center_world"):
		var center_value: Variant = map_root.call("get_map_center_world")
		if center_value is Vector3:
			center = center_value

	global_position = center + Vector3(initial_horizontal_offset, initial_height, initial_depth_offset)
	look_at(center, Vector3.UP)
