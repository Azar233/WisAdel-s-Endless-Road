extends CharacterBody2D
class_name Player

const NORMAL_ANIMATION_PREFIX := &"normal"

const BULLET_SCENE := preload("res://scene/bullet.tscn")
const ARMED_ANIMATION_PREFIX := &"armed"
const DEFAULT_MOVE_SPEED_MULTIPLIER := 1.0
const DEFAULT_FIRE_RATE_MULTIPLIER := 1.0
const SPIRAL_PHASE_STEP := PI / 12
const BLINK_ENABLED_SHADER_PARAMETER := &"blink_enabled"
const WORLD_COLLISION_MASK := 1

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
@export var max_health: int = 5
@export var invincibility_duration: float = 1.0

# 运行时变量
var current_health: int = 0
var invincibility_time_left: float = 0.0
var is_dead: bool = false

@export var fire_interval: float = 0.18
@export var bullet_spawn_distance: float = 18.0



func _ready() -> void:
	current_health = maxi(max_health, 1)
	shooting_timer.one_shot = true
	shooting_timer.wait_time = _get_effective_fire_interval()
	_set_hurt_blink_enabled(false)
	_update_animation()
	_update_armed_effect()

func _physics_process(delta: float) -> void:
	# 更新无敌时间
	_update_invincibility(delta)
	# 更新道具效果
	_update_pickup_effects(delta)
	
	if is_dead:
		velocity = Vector2.ZERO
		return

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
	_fire_bullets(shoot_direction)
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
	
	
# 统一伤害入口让玩家受伤
func apply_damage(amount: int) -> bool:
	# 防御性检测
	if is_dead:
		return false
	if amount <= 0:
		return false
	if invincibility_time_left > 0.0:
		return false
	
	current_health = maxi(current_health - amount, 0)
	if current_health <= 0:
		_die()
		return false
	_start_invincibility()
	return true

# 查询玩家生命值接口
func get_current_health() -> int:
	return current_health


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
	if not _can_spawn_bullet(shoot_direction):
		return false
	
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

# 检查子弹出生点是否有碰撞遮挡
func _can_spawn_bullet(shoot_direction: Vector2) -> bool:
	var spawn_position := global_position + shoot_direction * bullet_spawn_distance
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return true
	
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		spawn_position,
		WORLD_COLLISION_MASK
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	
	var hit_result: Dictionary = space_state.intersect_ray(query)
	return hit_result.is_empty()

# 螺旋状态下旋转发射子弹
func _try_auto_spiral_shoot() -> void:
	if not shooting_timer.is_stopped():
		return
	
	var spiral_direction := Vector2.RIGHT.rotated(spiral_phase)
	_fire_bullets(spiral_direction)
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

# 更新玩家无敌时间
func _update_invincibility(delta: float) -> void:
	if invincibility_time_left <= 0.0:
		return
	
	invincibility_time_left = maxf(invincibility_time_left - delta, 0.0)
	if invincibility_time_left > 0.0:
		return 
	
	_set_hurt_blink_enabled(false)


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


# 开启玩家受伤后的无敌闪烁状态
func _start_invincibility() -> void:
	invincibility_time_left = maxf(invincibility_duration, 0.0)
	_set_hurt_blink_enabled(invincibility_time_left > 0.0)

# 统一设置玩家手机闪烁开关
func _set_hurt_blink_enabled(enabled: bool) -> void:
	var sprite_material := body_sprite.material as ShaderMaterial
	if sprite_material != null:
		sprite_material.set_shader_parameter(BLINK_ENABLED_SHADER_PARAMETER, enabled)

# 玩家死亡
func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	invincibility_time_left = 0.0
	_set_hurt_blink_enabled(false)
	shooting_timer.stop()
	armed_effect_sprite.visible = false
	armed_effect_sprite.stop()

	

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
	
	
	
	







	
