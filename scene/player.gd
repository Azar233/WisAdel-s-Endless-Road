extends CharacterBody2D
class_name Player

const NORMAL_ANIMATION_PREFIX := &"normal"

const BULLET_SCENE := preload("res://scene/bullet.tscn")
const ARMED_ANIMATION_PREFIX := &"armed"
const DEFAULT_MOVE_SPEED_MULTIPLIER := 1.0
const DEFAULT_FIRE_RATE_MULTIPLIER := 1.0
const SPIRAL_PHASE_STEP := PI / 12


# 角色动画节点
@onready var body_sprite: AnimatedSprite2D = $BodySprite2D
# 浮游炮动画节点aa
@onready var armed_effect_sprite:AnimatedSprite2D = $ArmedEffectSprite2D
# 射击冷却计时器
@onready var shooting_timer: Timer = $ShootingTimer

# 当前朝向后缀
var facing_suffix: StringName = &"right"

# 当前移速倍率
var current_move_speed_multiplier: float = DEFAULT_MOVE_SPEED_MULTIPLIER
# 普通射速道具提供的射速倍率
var rapid_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLIER
# 形态道具提供的射速倍率
var form_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLIER
# 当前玩家形态
var current_form_mode: int = PickupConfig.PlayerFormMode.NORMAL
# 当前弹幕模式
var current_shot_pattern: int = PickupConfig.ShotPattern.NORMAL
# 三类buff的持续时间
var speed_buff_time_left: float = 0.0
var rapid_buff_time_left: float = 0.0
var form_buff_time_left: float = 0.0
# 螺旋弹幕的相位
var spiral_phase: float = 0.0

# 参数设置
@export var move_speed: float = 120.0
@export var fire_interval: float = 0.18
@export var bullet_spawn_distance: float = 18.0



func _ready() -> void:
	shooting_timer.one_shot = true
	shooting_timer.wait_time = _get_effective_fire_interval()
	_update_animation()
	_update_armed_effect()

func _physics_process(delta: float) -> void:
	# 更新道具效果
	_update_pickup_effects(delta)
	
	# 读取移动方向
	var move_input := Input.get_vector("move_left","move_right","move_up","move_down")
	# 读取射击方向
	var shoot_input:= Input.get_vector("shoot_left","shoot_right","shoot_up","shoot_down")
	
	velocity = move_input * _get_effective_move_speed()
	move_and_slide()
	
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		_try_auto_spiral_shoot()
	elif shoot_input != Vector2.ZERO:
		_try_shoot(shoot_input)
	
	_update_facing(move_input,shoot_input)	
	_update_animation()
	_update_armed_effect()
	
func _update_animation() -> void:
	var animation_name := StringName("%s_%s" % [_get_animation_prefix(), facing_suffix])
	
	if not body_sprite.sprite_frames.has_animation(animation_name):
		var fallback_animation_name := StringName("%s_%s" % [NORMAL_ANIMATION_PREFIX, facing_suffix])
		if not body_sprite.sprite_frames.has_animation(fallback_animation_name):
			push_warning("Missing player animation: %s" % animation_name)
			return
		animation_name = fallback_animation_name
	
	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)

# 射击方向优先于移动方向
func _update_facing(move_input: Vector2, shoot_input: Vector2) -> void:
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		if move_input != Vector2.ZERO:
			facing_suffix = _vector_to_facing_suffix(move_input)
		return
	
	if shoot_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(shoot_input)
	elif move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)
		
# 尝试发射子弹
func _try_shoot(shoot_input: Vector2) -> void:
	# 冷却结束发射下一颗子弹
	if not shooting_timer.is_stopped():
		return
	
	var shoot_direction := shoot_input.normalized()
	var has_spawn_bullet := _fire_bullets(shoot_direction)
	if has_spawn_bullet:
		shooting_timer.start(_get_effective_fire_interval())

# 道具的统一入口
func apply_pickup(config: PickupConfig) -> bool:
	if config == null:
		return false
	# 道具是否被拾取的标志
	var applied := false
	# 射速参数是否变化
	var should_refresh_shooting_timer := false
	# 本次buff持续时间
	var buff_duration := maxf(config.duration, 0.0)
	var has_form_ovverride := (
		config.player_form_mode != PickupConfig.PlayerFormMode.NORMAL
		or config.shot_pattern != PickupConfig.ShotPattern.NORMAL
	)
	var has_fire_rate_override := not is_equal_approx(
		config.fire_rate_multiplier,
		DEFAULT_FIRE_RATE_MULTIPLIER
	)
	
	if not is_equal_approx(config.move_speed_multiplier, DEFAULT_MOVE_SPEED_MULTIPLIER):
		current_move_speed_multiplier = config.move_speed_multiplier
		speed_buff_time_left = buff_duration
		applied = true
		
	if has_fire_rate_override and not has_form_ovverride:
		rapid_fire_rate_multiplier = config.fire_rate_multiplier
		rapid_buff_time_left = buff_duration
		should_refresh_shooting_timer = true
		applied = true
		
	if has_form_ovverride:
		current_form_mode = config.player_form_mode
		current_shot_pattern = config.shot_pattern
		form_fire_rate_multiplier = (
			config.fire_rate_multiplier if has_fire_rate_override else DEFAULT_FIRE_RATE_MULTIPLIER
		)
		form_buff_time_left = buff_duration
		# 相位角重置为0
		spiral_phase = 0.0
		should_refresh_shooting_timer = true
		applied = true
	
	if should_refresh_shooting_timer:
		_refresh_shooting_timer_wait_time()
	
	return applied
	
	
# 发射子弹
func _fire_bullets(base_direction: Vector2) -> bool:
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		# 螺旋发射前向后向两颗子弹
		var has_spawned_forward_bullet := _spawn_bullet(base_direction)
		var has_spawned_backward_bullet := _spawn_bullet(base_direction.rotated(PI)) 
		spiral_phase = wrapf(spiral_phase + SPIRAL_PHASE_STEP, 0.0, TAU)
		return has_spawned_forward_bullet or has_spawned_backward_bullet
	return _spawn_bullet(base_direction)

# 实例化一颗子弹
func  _spawn_bullet(shoot_direction: Vector2) -> bool:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	if bullet == null:
		return false
	
	bullet.top_level = true	
	bullet.setup(shoot_direction)
	
	# 子弹挂载当前场景，而不是玩家
	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		return false
	
	spawn_parent.add_child(bullet)
	bullet.global_position = global_position + shoot_direction * bullet_spawn_distance
	return true
	
# 螺旋状态下旋转发射子弹
func _try_auto_spiral_shoot() -> void:
	if not shooting_timer.is_stopped():
		return
	
	var spiral_direction := Vector2.RIGHT.rotated(spiral_phase)
	var has_spawned_bullet := _fire_bullets(spiral_direction)
	if has_spawned_bullet:
		shooting_timer.start(_get_effective_fire_interval())

# 每帧更新道具buff的剩余时间，到期后恢复默认
func _update_pickup_effects(delta: float) -> void:
	# 移速buff处理
	if speed_buff_time_left > 0.0:
		speed_buff_time_left = maxf(speed_buff_time_left - delta, 0.0)
		if speed_buff_time_left <= 0.0:
			current_move_speed_multiplier = DEFAULT_MOVE_SPEED_MULTIPLIER
	# 射速buff处理
	if rapid_buff_time_left > 0.0:
		rapid_buff_time_left = maxf(rapid_buff_time_left - delta, 0.0)
		if rapid_buff_time_left <= 0.0:
			rapid_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLIER
			_refresh_shooting_timer_wait_time()
	# 强化buff处理
	if form_buff_time_left > 0.0:
		form_buff_time_left = maxf(form_buff_time_left - delta, 0.0)
		if form_buff_time_left <= 0.0:
			current_form_mode = PickupConfig.PlayerFormMode.NORMAL
			current_shot_pattern = PickupConfig.ShotPattern.NORMAL
			form_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLIER
			spiral_phase = 0.0
			_refresh_shooting_timer_wait_time() 


func _get_effective_move_speed() -> float:
	return move_speed * current_move_speed_multiplier

# 计算有效开火间隔,射速倍率越高，开火间隔越短
func _get_effective_fire_interval() -> float:
	return maxf(fire_interval / _get_effective_fire_rate_multiplier(), 0.01)

# 强化形态下优先使用自带射速倍率，否则退回普通倍率
func _get_effective_fire_rate_multiplier() -> float:
	if _has_active_form_override():
		return maxf(form_fire_rate_multiplier, 0.01)
	
	return maxf(rapid_fire_rate_multiplier, 0.01)

# 只要玩家处于特殊形式，视为强化生效
func _has_active_form_override() -> bool:
	if current_form_mode != PickupConfig.PlayerFormMode.NORMAL or current_shot_pattern != PickupConfig.ShotPattern.NORMAL:
		return true
	
	return false
	
# 统一刷新射击计时器的基础间隔
func _refresh_shooting_timer_wait_time() -> void:
	var new_interval :=	_get_effective_fire_interval()
	shooting_timer.wait_time = new_interval
	
	# 如果玩家在冷却中拾取了更快射速buff，需要让冷却效果缩减
	if shooting_timer.is_stopped():
		return
	if shooting_timer.time_left <= new_interval:
		return
	shooting_timer.start(new_interval)

# 根据当前形态选择动画前缀
func _get_animation_prefix() -> StringName:
	if current_form_mode == PickupConfig.PlayerFormMode.ARMED:
		return ARMED_ANIMATION_PREFIX
		
	return NORMAL_ANIMATION_PREFIX

# 强化形态显示浮游炮动画
func _update_armed_effect() -> void:
	var is_armed := current_form_mode == PickupConfig.PlayerFormMode.ARMED
	
	if not is_armed:
		if armed_effect_sprite.visible:
			armed_effect_sprite.visible = false
		if armed_effect_sprite.is_playing():
			armed_effect_sprite.stop()
		return
	
	if not armed_effect_sprite.visible:
		armed_effect_sprite.visible = true
	if armed_effect_sprite.is_playing():
		return
	if armed_effect_sprite.sprite_frames == null:
		return
		
	if armed_effect_sprite.sprite_frames.has_animation("&default"):
		armed_effect_sprite.play("&default")
	

# 将二维vec映射为四方动画
func _vector_to_facing_suffix(direction: Vector2) -> StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0.0 else &"left"
	return &"down" if direction.y> 0.0 else &"up"
	
	
	
	







	
