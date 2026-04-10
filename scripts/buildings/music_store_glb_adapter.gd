@tool
extends Node3D

## 作用：为外部 GLB 音乐商店模型提供地图放置适配接口。
## 使用方法：将脚本挂在包装场景根节点，地图放置系统可直接调用占地与入口方法。
## 输入：占地尺寸、格子大小、模型缩放、碰撞高度等参数。
## 输出：更新模型变换、碰撞体和入口标记。
class_name MusicStoreGLBAdapter

@export var cell_size: float = 1.6
@export var footprint_size: Vector2i = Vector2i(4, 4)
@export var model_scale: float = 1.0
@export var model_y_offset: float = 0.0
@export var collision_height: float = 4.2

@onready var model_root: Node3D = $ModelRoot
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D
@onready var entrance_marker: Marker3D = $EntranceMarker


func _ready() -> void:
	_apply_model_transform()
	_update_collision_shape()
	_update_entrance_marker()


## 作用：返回建筑占地格子尺寸，供地图建造逻辑判定占用。
## 使用方法：地图放置脚本在落地前调用。
## 输入：无。
## 输出：占地宽高（格）。
func get_footprint_size() -> Vector2i:
	return footprint_size


## 作用：返回建筑入口世界坐标，供后续交互或寻路系统使用。
## 使用方法：外部系统在建筑实例化后调用。
## 输入：无。
## 输出：入口世界坐标。
func get_entrance_world_position() -> Vector3:
	return entrance_marker.global_position


## 作用：应用模型缩放与垂直偏移，确保 GLB 与地图尺度匹配。
## 使用方法：仅在初始化时调用。
## 输入：无。
## 输出：无。
func _apply_model_transform() -> void:
	if model_root == null:
		return
	model_root.scale = Vector3.ONE * model_scale
	model_root.position = Vector3(0.0, model_y_offset, 0.0)


## 作用：依据占地与高度更新碰撞体，保证放置和点击检测正确。
## 使用方法：仅在初始化时调用。
## 输入：无。
## 输出：无。
func _update_collision_shape() -> void:
	if collision_shape == null:
		return

	var width: float = float(footprint_size.x) * cell_size
	var depth: float = float(footprint_size.y) * cell_size
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, collision_height, depth)
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, collision_height * 0.5, 0.0)


## 作用：更新入口标记到建筑前方，便于角色从门口方向接近。
## 使用方法：仅在初始化时调用。
## 输入：无。
## 输出：无。
func _update_entrance_marker() -> void:
	if entrance_marker == null:
		return
	var depth: float = float(footprint_size.y) * cell_size
	entrance_marker.position = Vector3(0.0, 0.0, depth * 0.62)
