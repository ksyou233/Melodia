extends Node3D

## 作用：生成 2.5D 地图地块，并提供可视化测试入口。
## 使用方法：将脚本挂载到地图根节点，运行场景后会自动按参数生成地块。
## 输入：导出参数（地图宽高、格子尺寸、随机种子、地形高度层级）。
## 输出：地图生成统计字典（地块总数、地图尺寸、种子）。
class_name MapOverworld25D

@export var grid_width: int = 18
@export var grid_height: int = 14
@export var cell_size: float = 1.6
@export var random_seed: int = 20260410
@export var auto_generate_on_ready: bool = true
@export var generate_collision: bool = false
@export var base_tile_height: float = 0.2
@export var noise_frequency: float = 0.09
@export var height_curve_power: float = 1.15
@export var height_levels: PackedFloat32Array = PackedFloat32Array([0.0, 0.4, 0.8, 1.2])

@onready var tiles_root: Node3D = $TilesRoot
@onready var buildings_root: Node3D = $BuildingsRoot

var _palette: Array[Color] = [
	Color("4f7f4f"),
	Color("6ea76a"),
	Color("8ec97f"),
	Color("c5d88a")
]
var _render_root: Node3D
var _collision_root: Node3D
var _last_generated_tile_count: int = 0

func _ready() -> void:
	_ensure_generation_roots()
	_setup_world_visuals()
	if auto_generate_on_ready:
		var result: Dictionary = generate_map()
		print("[MapOverworld25D] 生成完成: ", result)


## 作用：清理旧地块后重新生成地图，便于重复测试。
## 使用方法：可在运行时手动调用，例如通过调试控制台触发。
## 输入：无（使用当前导出参数）。
## 输出：返回生成结果，用于自动化测试断言。
func generate_map() -> Dictionary:
	_clear_tiles()

	var level_count: int = height_levels.size()
	if level_count <= 0:
		_last_generated_tile_count = 0
		return {
			"tile_count": 0,
			"grid_width": grid_width,
			"grid_height": grid_height,
			"seed": random_seed
		}

	var noise := FastNoiseLite.new()
	noise.seed = random_seed
	noise.frequency = noise_frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var created_tiles: int = 0
	for z in range(grid_height):
		for x in range(grid_width):
			var level_index: int = _sample_level_index(noise, x, z, level_count)
			var elevation: float = height_levels[level_index]
			var tile_origin := Vector3(x * cell_size, 0.0, z * cell_size)
			_create_render_tile(tile_origin, elevation, level_index)
			if generate_collision:
				_create_collision_tile(tile_origin, elevation)
			created_tiles += 1

	_last_generated_tile_count = created_tiles

	return {
		"tile_count": created_tiles,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"seed": random_seed,
		"render_mode": "mesh"
	}


## 作用：执行可视化脚本测试所需的最小检查，验证地图场景结构。
## 使用方法：测试脚本可直接调用该函数读取检查结果。
## 输入：无。
## 输出：包含通过标记与统计信息的字典。
func run_visual_test() -> Dictionary:
	var expected_count: int = grid_width * grid_height
	var actual_count: int = _last_generated_tile_count
	var camera_exists: bool = has_node("CameraRig/Camera3D")
	var render_layer_count: int = _render_root.get_child_count() if _render_root != null else 0

	return {
		"pass": actual_count == expected_count and camera_exists,
		"expected_tile_count": expected_count,
		"actual_tile_count": actual_count,
		"camera_exists": camera_exists,
		"render_layer_count": render_layer_count
	}


## 作用：返回地图中心点世界坐标，供相机初始化或测试脚本定位使用。
## 使用方法：外部节点可直接调用该函数获取当前网格中心。
## 输入：无。
## 输出：地图中心点的世界坐标。
func get_map_center_world() -> Vector3:
	var center_x: float = (float(grid_width - 1) * cell_size) * 0.5
	var center_z: float = (float(grid_height - 1) * cell_size) * 0.5
	return global_position + Vector3(center_x, 0.0, center_z)


## 作用：将网格坐标转换为地图世界坐标，统一建筑与特效的落点计算。
## 使用方法：外部系统可先调用此函数，再决定是否实例化场景。
## 输入：grid_x 和 grid_z（格子坐标）。
## 输出：对应的世界坐标。
func grid_to_world(grid_x: int, grid_z: int) -> Vector3:
	return global_position + Vector3(float(grid_x) * cell_size, 0.0, float(grid_z) * cell_size)


## 作用：按网格坐标实例化建筑场景，便于后续直接把模型加载进地图。
## 使用方法：传入 PackedScene 与目标网格坐标，返回建筑节点引用。
## 输入：building_scene（建筑场景）、grid_x/grid_z（目标格子）、y_offset（高度偏移）。
## 输出：成功时返回 Node3D，失败时返回 null。
func place_building_scene(building_scene: PackedScene, grid_x: int, grid_z: int, y_offset: float = 0.0) -> Node3D:
	if building_scene == null:
		return null

	var instance := building_scene.instantiate() as Node3D
	if instance == null:
		return null

	instance.position = Vector3(float(grid_x) * cell_size, y_offset, float(grid_z) * cell_size)
	buildings_root.add_child(instance)
	return instance

## 作用：创建单个可渲染地块（轻量 Mesh 节点），兼顾性能与稳定性。
## 使用方法：由 generate_map 在每个网格坐标调用。
## 输入：地块原点位置、地块抬升高度、高度层级索引。
## 输出：无。
func _create_render_tile(tile_origin: Vector3, elevation: float, level_index: int) -> void:
	var box_height: float = base_tile_height + elevation
	var renderer := MeshInstance3D.new()
	renderer.name = "Tile_%d" % level_index

	var box := BoxMesh.new()
	box.size = Vector3(cell_size, box_height, cell_size)
	renderer.mesh = box
	renderer.material_override = _build_tile_material(level_index)
	renderer.position = tile_origin + Vector3(0.0, box_height * 0.5, 0.0)

	_render_root.add_child(renderer)


## 作用：按地块位置生成可选碰撞体，供后续点击拾取与放置测试使用。
## 使用方法：当 generate_collision 为 true 时由 generate_map 调用。
## 输入：地块原点位置与该地块抬升高度。
## 输出：无。
func _create_collision_tile(tile_origin: Vector3, elevation: float) -> void:
	var box_height: float = base_tile_height + elevation
	var body := StaticBody3D.new()
	body.name = "CollisionBody"

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(cell_size, box_height, cell_size)
	collision.shape = box_shape
	collision.position = Vector3(0.0, box_height * 0.5, 0.0)
	body.add_child(collision)

	body.position = tile_origin
	_collision_root.add_child(body)


## 作用：根据高度层级生成地块材质，提升 2.5D 地图层次感。
## 使用方法：仅供 _create_render_tile 内部调用。
## 输入：高度层级索引。
## 输出：标准材质实例。
func _build_tile_material(level_index: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var color_index: int = clamp(level_index, 0, _palette.size() - 1)
	material.albedo_color = _palette[color_index]
	material.roughness = lerpf(0.92, 0.72, float(color_index) / float(max(_palette.size() - 1, 1)))
	material.metallic = 0.0
	material.specular = 0.35
	material.ao_enabled = true
	material.ao_light_affect = 0.22
	return material


## 作用：根据高度采样结果计算地块层级，生成更平滑且可复现的地形分布。
## 使用方法：仅供 generate_map 内部调用。
## 输入：噪声对象、格子坐标、层级数量。
## 输出：地块层级索引。
func _sample_level_index(noise: FastNoiseLite, x: int, z: int, level_count: int) -> int:
	var noise_value: float = noise.get_noise_2d(float(x), float(z))
	var normalized: float = (noise_value + 1.0) * 0.5
	var curved: float = pow(normalized, height_curve_power)
	var index: int = int(floor(curved * float(level_count)))
	return clamp(index, 0, level_count - 1)

## 作用：确保渲染层与碰撞层节点存在，便于分层清理和调试。
## 使用方法：在 _ready 和 _clear_tiles 时自动调用。
## 输入：无。
## 输出：无。
func _ensure_generation_roots() -> void:
	if _render_root == null:
		if has_node("TilesRoot/RenderRoot"):
			_render_root = get_node("TilesRoot/RenderRoot") as Node3D
		else:
			_render_root = Node3D.new()
			_render_root.name = "RenderRoot"
			tiles_root.add_child(_render_root)

	if _collision_root == null:
		if has_node("TilesRoot/CollisionRoot"):
			_collision_root = get_node("TilesRoot/CollisionRoot") as Node3D
		else:
			_collision_root = Node3D.new()
			_collision_root.name = "CollisionRoot"
			tiles_root.add_child(_collision_root)


## 作用：统一初始化环境与主光源参数，提升 2.5D 地图阴影层次和整体氛围。
## 使用方法：在 _ready 阶段自动调用。
## 输入：无。
## 输出：无。
func _setup_world_visuals() -> void:
	var light := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light != null:
		light.scale = Vector3.ONE
		light.rotation_degrees = Vector3(-52.0, -45.0, 0.0)
		light.light_energy = 1.25
		light.light_color = Color("fff0cf")
		light.shadow_enabled = true

	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null:
		return

	var env: Environment = world_environment.environment
	if env == null:
		return

	env.ambient_light_energy = 0.42
	env.fog_enabled = true
	env.fog_light_color = Color("d9e6ee")
	env.fog_light_energy = 0.22
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.45


## 作用：删除历史生成的地块，避免重复堆叠造成测试结果错误。
## 使用方法：仅供 generate_map 内部调用。
## 输入：无。
## 输出：无。
func _clear_tiles() -> void:
	_ensure_generation_roots()
	for child in _render_root.get_children():
		child.free()
	for child in _collision_root.get_children():
		child.free()
	_last_generated_tile_count = 0
