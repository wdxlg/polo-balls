extends ball

@export_range(0.1,30.0,0.1) var lifetime:float = 2.6
# 保留旧属性以兼容已有场景/Inspector；新版穿门直接“刷新回完整基础寿命”。
@export_range(0.0,10.0,0.1) var portal_extra_lifetime:float = 0.0
@export_range(0.1,60.0,0.1) var max_total_lifetime:float = 8.0
@export_range(-20.0,20.0,0.1) var wrench_spin_speed:float = 8.2

var _life_left:float = 0.0


func _ready() -> void:
	super._ready()
	_life_left = maxf(lifetime,0.1)


func _physics_process(delta:float) -> void:
	# 视觉旋转每个客户端本地执行；根节点仍由权威端的 ball.tick_physics 正常移动/反弹。
	if image is Sprite2D:
		(image as Sprite2D).rotation += wrench_spin_speed * delta

	if not is_multiplayer_authority():
		return
	_life_left -= delta
	if _life_left <= 0.0:
		Game.free_node(self)


# “只会在一定时间后消失”：其它攻击不能把它提前打掉。
func take_damage(_damage:float,_ignore_block:bool = false) -> void:
	pass


func hit_white(_ignore_block:bool = false) -> void:
	pass


func on_scientist_portal_pass() -> void:
	# 现在基础寿命更短，但每次成功穿门都会刷新回完整寿命。
	# max_total_lifetime 继续作为单次剩余寿命的安全上限，兼容旧 Inspector。
	_life_left = minf(maxf(lifetime,0.1),maxf(max_total_lifetime,lifetime))


func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	# 科学家扳手是“正常反弹弹丸”：撞墙和撞角色都继续复用 ball 的反弹逻辑，
	# 命中不会因为伤害结算而销毁。
	super.when_collide(speed,collision)


func Die() -> void:
	if is_instance_valid(self):
		Game.free_node(self)
