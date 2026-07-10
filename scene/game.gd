extends Node2D

const RESULT_TITLE_WIN := "你赢了"
const RESULT_TITLE_LOSE := "你输了"
const RESULT_MESSAGE_WIN := "你成功坚持到了倒计时结束"
const RESULT_MESSAGE_LOSE := "玩家生命值归零"
const RESULT_OK_BUTTON_TEXT := "结束游戏"


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

@export_group("关卡UI")
# 关卡倒计时
@export_range(1.0, 3600.0, 1.0, "or_greater") var stage_duration: float = 60.0

# 主场景中的核心引用
@onready var player: Player = $Player
@onready var enemy_container: Node2D = $EnemyContainer
@onready var enemy_spawn_points_root: Node2D = $EnemySpawnPoints
@onready var enemy_spawn_timer: Timer = $EnemySpawnTimer
@onready var life_count_label: Label = $HUDLayer/LifeCountLabel
@onready var time_bar: Sprite2D = $HUDLayer/TimeBar
@onready var result_dialog: AcceptDialog = $AcceptDialog
@onready var bgm_player: AudioStreamPlayer = $AudioContainer/BgmPlayer
@onready var result_win_sfx_player: AudioStreamPlayer = $AudioContainer/ResultWinSfxPlayer
@onready var result_lose_sfx_player: AudioStreamPlayer = $AudioContainer/ResultLoseSfxPlayer



# 随机数生成器
var random_generator: RandomNumberGenerator = RandomNumberGenerator.new()
# 缓存出生点，避免每次遍历场景树
var enemy_spawn_points: Array[Marker2D] = []
# 缓存有效敌人配置
var available_enemy_configs: Array[EnemyConfig] = []
# 关卡倒计时
var stage_time_left: float = 0.0
# timebar原始横向缩放比例
var time_bar_full_sale_x: float = 1.0
# timebar左边缘位置
var time_bar_left_edge_x: float = 0.0
# timebar原始宽度
var time_bar_texture_width: float = 0.0
# 是否进入结算状态
var is_result_displayed: bool = false

func _ready() -> void:
	random_generator.randomize()
	
	_configure_result_dialog()
	_setup_hud()
	
	_collect_enemy_spawn_points()
	_collect_enemy_configs()
	_configure_enemy_spawn_timer()
	_spawn_initial_enemies()
	_start_enemy_spawn_timer()


func _process(delta: float) -> void:
	if is_result_displayed:
		return
	
	_update_stage_timer(delta)
	_update_spawn_interval()
	_update_hud()
	_check_game_result()


# 配置结算弹窗
func _configure_result_dialog() -> void:
	result_dialog.dialog_close_on_escape = false
	result_dialog.ok_button_text = RESULT_OK_BUTTON_TEXT
	result_dialog.hide()
	
	if not result_dialog.confirmed.is_connected(_on_result_dialog_exit_requested):
		result_dialog.confirmed.connect(_on_result_dialog_exit_requested)
	if not result_dialog.close_requested.is_connected(_on_result_dialog_exit_requested):
		result_dialog.close_requested.connect(_on_result_dialog_exit_requested)
	if not result_dialog.canceled.is_connected(_on_result_dialog_exit_requested):
		result_dialog.canceled.connect(_on_result_dialog_exit_requested)

# hud设置
func _setup_hud() -> void:
	stage_time_left = maxf(stage_duration, 0.0)
	time_bar_full_sale_x = time_bar.scale.x
	if time_bar.texture != null:
		time_bar_texture_width = time_bar.texture.get_width()
	if time_bar.centered:
		time_bar_left_edge_x = time_bar.position.x - (time_bar_texture_width * time_bar_full_sale_x * 0.5)
	else:
		time_bar_left_edge_x = time_bar.position.x
	
	_update_hud()

# 倒计时更新
func _update_stage_timer(delta: float) -> void:
	if stage_time_left <= 0.0:
		stage_time_left = 0.0
		return
	stage_time_left = maxf(stage_time_left - delta, 0.0)

# hud更新
func _update_hud() -> void:
	_update_life_count_label()
	_update_time_bar()

func _update_life_count_label() -> void:
	life_count_label.text = "x %d" % _get_player_current_health()

func _update_time_bar() -> void:
	var fill_ratio := 0.0
	if stage_duration > 0.0:
		fill_ratio = clampf(stage_time_left / stage_duration, 0.0, 1.0)
	
	time_bar.scale.x = time_bar_full_sale_x
	
	if not time_bar.centered:
		time_bar.position.x = time_bar_left_edge_x
		return
	
	var current_width := time_bar_texture_width * time_bar.scale.x
	time_bar.position.x = time_bar_left_edge_x + (current_width * 0.5)
	
# 判断游戏状态
func _check_game_result() -> void:
	if stage_time_left <= 0.0:
		_show_result_dialog(RESULT_TITLE_WIN, RESULT_MESSAGE_WIN)
		return
	
	if _get_player_current_health() <= 0:
		_show_result_dialog(RESULT_TITLE_LOSE, RESULT_MESSAGE_LOSE)

# 展示结算弹窗
func _show_result_dialog(result_title: String, result_message: String) -> void:
	if is_result_displayed:
		return
	
	is_result_displayed = true
	result_dialog.title = result_title
	result_dialog.dialog_text = result_message
	
	_play_result_audio(result_title)
	
	_stop_world()
	result_dialog.popup_centered()
	
	var ok_button := result_dialog.get_ok_button()
	if ok_button != null:
		ok_button.grab_focus()
	
# 统一停止世界，让结算窗口唯一交互
func _stop_world() -> void:
	enemy_spawn_timer.stop()
	player.stop_runtime_audio()
	Engine.time_scale = 0.0
	get_tree().paused = true

func _play_result_audio(result_title: String) -> void:
	if bgm_player.playing:
		bgm_player.stop()
	
	if result_title == RESULT_TITLE_WIN:
		_play_sfx(result_win_sfx_player)
		return
	if result_title == RESULT_TITLE_LOSE:
		_play_sfx(result_lose_sfx_player)

func _play_sfx(audio_player: AudioStreamPlayer) -> void:
	if audio_player == null or audio_player.stream == null:
		return
	audio_player.stop()
	audio_player.play()

func _on_result_dialog_exit_requested() -> void:
	get_tree().quit()

func _get_player_current_health() -> int:
	return player.get_current_health()

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

	if stage_duration <= 0.0:
		return end_interval

	var difficulty_ratio := 1.0 - clampf(stage_time_left / stage_duration, 0.0, 1.0)
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
