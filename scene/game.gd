extends Node2D


# 默认敌人场景与配置
@export_group("刷怪资源")
@export var enemy_scene: PackedScene = preload("res://scene/enemy.tscn")
@export var enemy_configs: Array[EnemyConfig] = [
	preload("res://resources/config/enemy_basic.tres"),
	preload("res://resources/config/enemy_shelled.tres"),
	preload("res://resources/config/enemy_fast.tres"),
	preload("res://resources/config/enemy_bomber.tres"),
]

@export_group("刷怪节奏")
# 开局刷怪数
@export_range(0, 100, 1, "or_greater") var initial_spawn_count: int = 1
# 每次计时器触发时刷怪数
@export_range(1, 20, 1, "or_greater") var spawn_count_per_tick: int = 1
# 开局刷怪间隔
@export_range(0.1, 60, 0.1, "or_greater") var spawn_interval: float = 1.5
# 后期允许缩小到的最小刷怪间隔
@export_range(0.1, 60, 0.1, "or_greater") var min_spawn_interval: float = 0.6
# 场上允许最大敌人数
@export_range(1, 200, 1, "or_greater") var max_alive_enemies: int = 12
# 刷怪间隔从初始值到最小值的刷新时间
@export_range(1.0, 3600.0, 1.0, "or_greater") var spawn_acceleration_duration: float = 60.0

# 主场景中的核心引用
@onready var player: Player = $Player
@onready var enemy_container: Node2D = $EnemyContainer
@onready var enemy_spawn_points_root: Node2D = $EnemySpawnPoints
@onready var enemy_spawn_timer: Timer = $EnemySpawnTimer

# 随机数生成器
var random_generator: RandomNumberGenerator = RandomNumberGenerator.new()
# 缓存出生点，避免每次遍历场景树
var enemy_spawn_points: Array[Marker2D] = []
# 缓存有效敌人配置
var available_enemy_configs: Array[EnemyConfig] = []
# 当前游戏已运行时间
var game_time_elapsed: float = 0.0


func _ready() -> void:
	random_generator.randomize()
	_collect_enemy_spawn_points()
	_collect_enemy_configs()
	_configure_enemy_spawn_timer()
	_spawn_initial_enemies()
	_start_enemy_spawn_timer()


func _process(delta: float) -> void:
	game_time_elapsed += delta
	_update_spawn_interval()

# 收集出生点
func _collect_enemy_spawn_points() -> void:
	enemy_spawn_points.clear()

	for child in enemy_spawn_points_root.get_children():
		var spawn_point := child as Marker2D
		if spawn_point != null:
			enemy_spawn_points.append(spawn_point)

	if enemy_spawn_points.is_empty():
		push_warning("EnemySpawnPoints 下没有可用的Marker2D刷新点")

# 缓存有效的敌人配置
func _collect_enemy_configs() -> void:
	available_enemy_configs.clear()
	for enemy_config in enemy_configs:
		if enemy_config != null:
			available_enemy_configs.append(enemy_config)

	if available_enemy_configs.is_empty():
		push_warning("Game场景没有可用的敌人配置资源")

# 统一配置在主场景中的刷怪计时器
func _configure_enemy_spawn_timer() -> void:
	enemy_spawn_timer.one_shot = false
	enemy_spawn_timer.wait_time = _get_current_spawn_interval()

	if not enemy_spawn_timer.timeout.is_connected(_on_enemy_spawn_timer_timeout):
		enemy_spawn_timer.timeout.connect(_on_enemy_spawn_timer_timeout)


# 根据游戏时间逐渐缩短刷怪间隔
func _update_spawn_interval() -> void:
	var current_interval := _get_current_spawn_interval()
	if is_equal_approx(enemy_spawn_timer.wait_time, current_interval):
		return

	enemy_spawn_timer.wait_time = current_interval

	if enemy_spawn_timer.is_stopped():
		return
	if enemy_spawn_timer.time_left <= current_interval:
		return

	enemy_spawn_timer.start(current_interval)


# 计算当前刷怪时间间隔
func _get_current_spawn_interval() -> float:
	var start_interval := maxf(spawn_interval, 0.1)
	var end_interval := minf(maxf(min_spawn_interval, 0.1), start_interval)

	if spawn_acceleration_duration <= 0.0:
		return end_interval

	var difficulty_ratio := clampf(game_time_elapsed / spawn_acceleration_duration, 0.0, 1.0)
	return lerpf(start_interval, end_interval, difficulty_ratio)

# 初始化第一批敌人
func _spawn_initial_enemies() -> void:
	for _spawn_index in range(initial_spawn_count):
		if not _try_spawn_enemy():
			break

# 当前刷怪系统准备就绪再启动计时器
func _start_enemy_spawn_timer() -> void:
	if not _is_spawn_system_ready():
		return

	enemy_spawn_timer.start()

# 每次计时器触发，尝试刷新敌人
func _on_enemy_spawn_timer_timeout() -> void:
	for _spawn_index in range(spawn_count_per_tick):
		if not _try_spawn_enemy():
			break

# 尝试生成一个敌人，完成位置和玩家目标初始化
func _try_spawn_enemy() -> bool:
	# 防御性检测
	if not _is_spawn_system_ready():
		return false
	if _get_alive_enemy_count() >= max_alive_enemies:
		return false

	var spawn_point := _pick_spawn_point()
	if spawn_point == null:
		return false

	var enemy_config := _pick_enemy_config()
	if enemy_config == null:
		return false

	# 实例化敌人
	var enemy_instance := enemy_scene.instantiate() as Enemy
	if enemy_instance == null:
		push_warning("敌人场景实例化失败，请检查enemy_scene设置")
		return false

	enemy_container.add_child(enemy_instance)
	enemy_instance.global_position = spawn_point.global_position
	enemy_instance.setup(enemy_config, player)

	return true

# 防御性检测函数的实现
func _is_spawn_system_ready() -> bool:
	return (
		player != null
		and enemy_scene != null
		and not enemy_spawn_points.is_empty()
		and not available_enemy_configs.is_empty()
	)

func _pick_spawn_point() -> Marker2D:
	if enemy_spawn_points.is_empty():
		return null

	var random_index := random_generator.randi_range(0, enemy_spawn_points.size() -1)
	return enemy_spawn_points[random_index]

func _pick_enemy_config() -> EnemyConfig:
	if available_enemy_configs.is_empty():
		return null
	var random_index := random_generator.randi_range(0, available_enemy_configs.size() - 1)
	return available_enemy_configs[random_index]

# 只统计存在的敌人不计算死亡的
func _get_alive_enemy_count() -> int:
	var alive_enemy_count := 0

	for child in enemy_container.get_children():
		if child is Enemy:
			alive_enemy_count += 1

	return alive_enemy_count
