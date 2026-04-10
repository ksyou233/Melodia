extends Node

## 作用：在 2.5D 地图中提供可直接使用的建筑放置能力（鼠标点击放置）。
## 使用方法：挂载到地图场景后，运行时左键点击地图即可放置当前建筑。
## 输入：鼠标位置、地图参数、建筑场景资源。
## 输出：在地图 BuildingsRoot 下实例化建筑节点。
class_name BuildingPlacer25D

@export var map_path: NodePath = NodePath("..")
@export var camera_path: NodePath = NodePath("../CameraRig/Camera3D")
@export var default_building_scene: PackedScene = preload("res://scenes/buildings/music_store_glb.tscn")
@export var placement_y_offset: float = 0.0
@export var enable_debug_print: bool = true

var _map_root: MapOverworld25D
var _camera: Camera3D
var _current_building_scene: PackedScene
var _occupied_cells: Dictionary = {}
var _footprint_cache: Dictionary = {}


func _ready() -> void:
	_map_root = get_node_or_null(map_path) as MapOverworld25D
	_camera = get_node_or_null(camera_path) as Camera3D
	_current_building_scene = default_building_scene

	if _map_root == null:
		push_error("[BuildingPlacer25D] 无法找到地图节点，请检查 map_path 配置。")
	if _camera == null:
		push_error("[BuildingPlacer25D] 无法找到相机节点，请检查 camera_path 配置。")


## 作用：处理鼠标点击放置逻辑，实现“运行后可直接在地图上放建筑”。
## 使用方法：引擎自动调用；左键点击地图即可触发放置。
## 输入：InputEvent。
## 输出：无。
func _unhandled_input(event: InputEvent) -> void:
	if _map_root == null or _camera == null:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_get_hovered_control() != null:
			return

		var hit_position: Vector3 = _get_mouse_ground_intersection(event.position)
		var grid_pos: Vector2i = _world_to_grid(hit_position)
		_try_place_current_building(grid_pos)


## 作用：设置当前待放置建筑资源，便于后续切换不同建筑类型。
## 使用方法：外部系统可调用该函数切换待放置建筑。
## 输入：PackedScene 建筑场景。
## 输出：无。
func set_current_building_scene(building_scene: PackedScene) -> void:
	_current_building_scene = building_scene


## 作用：尝试在指定网格位置放置当前建筑，包含边界与占地冲突校验。
## 使用方法：内部在鼠标点击后调用。
## 输入：目标网格坐标。
## 输出：放置是否成功。
func _try_place_current_building(grid_pos: Vector2i) -> bool:
	if _current_building_scene == null:
		if enable_debug_print:
			print("[BuildingPlacer25D] 当前没有可放置的建筑场景。")
		return false

	var footprint: Vector2i = _get_scene_footprint(_current_building_scene)
	if not _can_place_footprint(grid_pos, footprint):
		if enable_debug_print:
			print("[BuildingPlacer25D] 放置失败，越界或占地冲突: ", grid_pos, " footprint=", footprint)
		return false

	var instance := _map_root.place_building_scene(_current_building_scene, grid_pos.x, grid_pos.y, placement_y_offset)
	if instance == null:
		if enable_debug_print:
			print("[BuildingPlacer25D] 放置失败，实例化返回 null。")
		return false

	_mark_footprint_occupied(grid_pos, footprint)
	if enable_debug_print:
		print("[BuildingPlacer25D] 放置成功: ", instance.name, " @ ", grid_pos)
	return true


## 作用：将鼠标屏幕坐标投射到地面平面（Y=0），得到地图点击点。
## 使用方法：内部在点击时调用。
## 输入：鼠标屏幕坐标。
## 输出：地面交点坐标（未命中时返回 Vector3.ZERO）。
func _get_mouse_ground_intersection(screen_pos: Vector2) -> Vector3:
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = _camera.project_ray_normal(screen_pos)
	var ground_plane := Plane(Vector3.UP, 0.0)
	var intersection: Variant = ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection is Vector3:
		return intersection
	return Vector3.ZERO


## 作用：把世界坐标转换为地图网格坐标，统一放置和占地计算基准。
## 使用方法：内部在点击后调用。
## 输入：世界坐标。
## 输出：网格坐标。
func _world_to_grid(world_pos: Vector3) -> Vector2i:
	var local_pos: Vector3 = world_pos - _map_root.global_position
	var gx: int = int(round(local_pos.x / _map_root.cell_size))
	var gz: int = int(round(local_pos.z / _map_root.cell_size))
	return Vector2i(gx, gz)


## 作用：读取建筑场景占地尺寸，若无接口则使用默认 1x1。
## 使用方法：放置前自动调用。
## 输入：建筑 PackedScene。
## 输出：占地宽高（格）。
func _get_scene_footprint(building_scene: PackedScene) -> Vector2i:
	var scene_key: String = building_scene.resource_path
	if scene_key != "" and _footprint_cache.has(scene_key):
		return _footprint_cache[scene_key]

	var temp_instance := building_scene.instantiate()
	if temp_instance == null:
		return Vector2i.ONE

	var footprint: Vector2i = Vector2i.ONE
	if temp_instance.has_method("get_footprint_size"):
		var value: Variant = temp_instance.call("get_footprint_size")
		if value is Vector2i:
			footprint = value

	temp_instance.queue_free()
	var final_footprint := Vector2i(max(1, footprint.x), max(1, footprint.y))
	if scene_key != "":
		_footprint_cache[scene_key] = final_footprint
	return final_footprint


## 作用：检查指定占地是否可放置，包含边界和占用冲突校验。
## 使用方法：放置前调用。
## 输入：放置起点网格、占地尺寸。
## 输出：是否允许放置。
func _can_place_footprint(origin: Vector2i, footprint: Vector2i) -> bool:
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			var x: int = origin.x + dx
			var z: int = origin.y + dz
			if x < 0 or z < 0 or x >= _map_root.grid_width or z >= _map_root.grid_height:
				return false
			if _occupied_cells.has(_cell_key(x, z)):
				return false
	return true


## 作用：将建筑占地范围登记为已占用，防止重复放置重叠。
## 使用方法：放置成功后调用。
## 输入：放置起点网格、占地尺寸。
## 输出：无。
func _mark_footprint_occupied(origin: Vector2i, footprint: Vector2i) -> void:
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			var x: int = origin.x + dx
			var z: int = origin.y + dz
			_occupied_cells[_cell_key(x, z)] = true


## 作用：构建网格唯一键，用于占用状态字典检索。
## 使用方法：内部占地校验与登记调用。
## 输入：网格坐标 x、z。
## 输出：字符串键。
func _cell_key(x: int, z: int) -> String:
	return "%s:%s" % [str(x), str(z)]
