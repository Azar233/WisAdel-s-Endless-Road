extends Resource
class_name PickupConfig

enum PickupType{
	SPEED,
	RAPID,
	SPIRAL,
}

enum PlayerFormMode{
	NORMAL,
	ARMED,
}

enum ShotPattern{
	NORMAL,
	SPIRAL,
}

@export_group("Basic_Info")
# 标记道具类型
@export var pickup_type: PickupType = PickupType.SPEED
# 显示名称
@export var display_name: String = "移速道具"
# 掉落权重
@export_range(0.0, 1000.0, 0.1, "or_greater") var drop_weight: float = 1.0

@export_group("Display_Resource")
@export var icon_texture: Texture2D

@export_group("Buff_Effect")
# 道具持续时间（seconds）
@export_range(0.0, 120.0, 0.1, "or_greater") var duration: float = 5.0
# 玩家移速倍率 1.x 表示提升x%
@export_range(0.1, 5.0, 0.05, "or_greater") var move_speed_multiplier: float = 1.0
# 玩家射速倍率
@export_range(0.1, 5.0, 0.05, "or_greater") var fire_rate_multiplier: float = 1.0

@export_group("Shape_And_Bullet")
@export var player_form_mode: PlayerFormMode = PlayerFormMode.NORMAL
@export var shot_pattern: ShotPattern = ShotPattern.NORMAL
