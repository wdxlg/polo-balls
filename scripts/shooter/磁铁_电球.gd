extends ball

@export_range(4.0,40.0,1.0) var visual_radius:float = 13.0
@export_range(0.1,10.0,0.1) var visual_spin_speed:float = 4.6

var _visual_phase:float = 0.0


func _ready() -> void:
	add_to_group("MagnetElectricBall")
	add_to_group("BattleTransient")
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	Max_health = 999999
	health = Max_health
	Hit_Audio = "balls_hit1"
	# 墙面反弹不需要死亡，也不播放角色身体的脚步/碰撞反馈音。
	Collide_Audio = ""
	super._ready()

	# 电球只需要自己的攻击 Hitbox；它本身不可被打掉。
	if self_hurtbox != null:
		self_hurtbox.monitoring = false
		self_hurtbox.monitorable = false
		self_hurtbox.collision_layer = 0
		self_hurtbox.collision_mask = 0

	# 使用圆形物理体和圆形攻击范围，让视觉/碰撞一致。
	var body_shape := CircleShape2D.new()
	body_shape.radius = maxf(visual_radius - 2.0,4.0)
	if collision_shape_2d != null:
		collision_shape_2d.shape = body_shape
		collision_shape_2d.position = Vector2.ZERO
		collision_shape_2d.scale = Vector2.ONE

	var hit_shape_node:CollisionShape2D = null
	if self_hitbox != null:
		hit_shape_node = self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if hit_shape_node != null:
		var attack_shape := CircleShape2D.new()
		attack_shape.radius = maxf(visual_radius + 2.0,6.0)
		hit_shape_node.shape = attack_shape
		hit_shape_node.position = Vector2.ZERO
		hit_shape_node.scale = Vector2.ONE

	if image != null:
		image.visible = false
	if health_bar != null:
		health_bar.visible = false

	if direction.length_squared() <= 0.000001:
		direction = Vector2.RIGHT
	queue_redraw()


func tick_physics(state:State,delta:float) -> void:
	_visual_phase += delta * visual_spin_speed
	queue_redraw()
	if not is_multiplayer_authority():
		return
	if direction.length_squared() <= 0.000001:
		direction = Vector2.RIGHT
	# 永久电球没有寿命计时，始终按自身速度飞行。
	super.tick_physics(state,delta)


func _draw() -> void:
	# 不依赖额外图片：亮蓝电球 + 两道旋转闪电，任何客户端都能稳定显示。
	var r:float = maxf(visual_radius,4.0)
	draw_circle(Vector2.ZERO,r,Color(0.12,0.72,1.0,0.24))
	draw_circle(Vector2.ZERO,r * 0.72,Color(0.46,0.90,1.0,0.88))
	draw_circle(Vector2.ZERO,r * 0.36,Color(0.92,0.99,1.0,1.0))
	draw_arc(Vector2.ZERO,r,0.0,TAU,24,Color(0.62,0.94,1.0,0.95),1.6,true)

	for branch:int in range(2):
		var base_angle:float = _visual_phase + float(branch) * PI
		var p0:Vector2 = Vector2.from_angle(base_angle) * (r * 0.20)
		var p1:Vector2 = Vector2.from_angle(base_angle + 0.38) * (r * 0.55)
		var p2:Vector2 = Vector2.from_angle(base_angle - 0.18) * (r * 0.92)
		draw_polyline(PackedVector2Array([p0,p1,p2]),Color(0.94,1.0,1.0,0.98),2.0,true)


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if not is_multiplayer_authority():
		return
	# 始终读取主人的当前伤害值；磁铁后续获得伤害增益时，永久电球会同步变强。
	if Master != null and is_instance_valid(Master):
		Damage = Master.Damage
	super(hurt)
	# 命中角色后不消失、不停下，继续飞行。


func take_damage(_damage:float,_ignore_block:bool = false) -> void:
	# 永久电球不可被伤害或消耗。
	pass


func when_collide(_speed:float,collision:KinematicCollision2D) -> void:
	if not is_multiplayer_authority() or collision == null:
		return
	var normal:Vector2 = collision.get_normal().normalized()
	if normal.length_squared() <= 0.000001:
		return
	if direction.dot(normal) < 0.0:
		direction = direction.bounce(normal).normalized()
	# 从接触面轻推开，避免在墙角因 safe_margin 连续卡住。
	global_position += direction * 1.5


func Die() -> void:
	# 不响应普通投射物的死亡流程；只有磁铁死亡/退出时由主人主动清理。
	pass
