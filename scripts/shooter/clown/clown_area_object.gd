extends Area2D

# 小丑场景物件：
# 0 香蕉皮：延迟激活，任何真实角色（自己/队友/敌人）都能踩。
# 1 彩带：V9.4 改成真正的抛物线投射。斜向射出 -> 重力下坠 -> 落到一定高度后消失；
#          对敌人低伤，首次有效命中后立即消失。

enum ObjectMode {
	BANANA,
	CONFETTI,
}

@export var object_mode:ObjectMode = ObjectMode.BANANA
@export var Master:ball = null
@export var Master_name:String = ""
@export var Team:String = ""
@export var texture_path:String = ""

@export_category("通用")
@export var life_time:float = 5.0

@export_category("香蕉")
@export var arm_delay:float = 0.75

@export_category("彩带")
@export var direction:Vector2 = Vector2.RIGHT
# V9.4 抛物线运动参数。
@export var initial_velocity:Vector2 = Vector2.ZERO
@export var projectile_gravity:float = 520.0
# 在这段时间以前绝不因为“落到出生点下方”而提前销毁，
# 用于保证按目标反求的完整抛物线至少能走到预定目标时间。
@export var minimum_flight_time:float = 0.0
@export var fall_delete_distance:float = 110.0
@export var spin_speed:float = 5.2
@export var damage_amount:float = 1.0

# 兼容旧场景/旧脚本留下的字段；V9.4 新生成彩带不再依赖它们。
@export var move_speed:float = 155.0
@export var travel_distance:float = 78.0
@export var fall_speed:float = 45.0

@export_category("视觉尺寸（像素长边）")
@export var banana_visual_size:float = 28.0
# V9.2：香蕉缩小；彩带保持可见，同时扩大“扫掠命中”容错。
@export var confetti_visual_size:float = 32.0
@export var confetti_sweep_radius:float = 26.0

@onready var sprite:Sprite2D = $Sprite2D

var elapsed:float = 0.0
var spawn_position:Vector2 = Vector2.ZERO
var armed:bool = false
var hit_ids:Dictionary = {}
var triggered:bool = false
var confetti_velocity:Vector2 = Vector2.ZERO


func _ready() -> void:
	spawn_position = global_position
	_apply_texture()

	area_entered.connect(_on_area_entered)

	if object_mode == ObjectMode.BANANA:
		monitoring = false
		modulate = Color(1.0,1.0,1.0,0.55)
		_arm_banana_after_delay()
	else:
		add_to_group("BattleTransient")
		monitoring = true
		armed = true
		confetti_velocity = initial_velocity
		if confetti_velocity.length_squared() <= 0.001:
			# 旧调用兜底：仍给它一个向前+向上的初速度。
			var fallback_dir:Vector2 = direction.normalized()
			if fallback_dir.length_squared() <= 0.001:
				fallback_dir = Vector2.RIGHT
			confetti_velocity = fallback_dir * maxf(move_speed,1.0) + Vector2.UP * maxf(fall_speed * 3.5,120.0)
			initial_velocity = confetti_velocity
		direction = confetti_velocity.normalized()


func _apply_texture() -> void:
	if sprite == null:
		return
	if texture_path == "" or not ResourceLoader.exists(texture_path):
		return

	var texture:Texture2D = load(texture_path)
	if texture == null:
		return

	sprite.texture = texture
	var size:Vector2 = texture.get_size()
	var max_side:float = maxf(size.x,size.y)
	if max_side <= 0.0:
		return

	var target_size:float = banana_visual_size if object_mode == ObjectMode.BANANA else confetti_visual_size
	sprite.scale = Vector2.ONE * (target_size / max_side)
	sprite.z_index = 10


func _arm_banana_after_delay() -> void:
	await get_tree().create_timer(maxf(arm_delay,0.0)).timeout
	if not is_instance_valid(self):
		return

	armed = true
	monitoring = true
	modulate = Color.WHITE

	# Area2D 的重叠列表只会在物理步骤中更新。
	# 开启 monitoring 后先等一个 physics frame，再补查一直站在香蕉上的角色。
	await get_tree().physics_frame
	if not is_instance_valid(self):
		return

	for area:Area2D in get_overlapping_areas():
		_try_trigger_area(area)
		if not is_instance_valid(self):
			return


func _physics_process(delta:float) -> void:
	elapsed += delta
	if elapsed >= life_time:
		if is_multiplayer_authority():
			Game.free_node(self)
		return

	if object_mode != ObjectMode.CONFETTI:
		return
	if not is_multiplayer_authority():
		return

	var before_move:Vector2 = global_position

	# V9.5：使用解析式计算位置，而不是逐帧 velocity += g*dt 再 position += v*dt。
	# p(t) = p0 + v0*t + 1/2*g*t^2
	# 因此轨迹严格是抛物线，并且不会因为物理帧率不同而改变弧线形状。
	var gravity_vec:Vector2 = Vector2.DOWN * maxf(projectile_gravity,0.0)
	global_position = (
		spawn_position
		+ initial_velocity * elapsed
		+ gravity_vec * (0.5 * elapsed * elapsed)
	)
	confetti_velocity = initial_velocity + gravity_vec * elapsed
	rotation += spin_speed * delta

	if confetti_velocity.length_squared() > 0.001:
		direction = confetti_velocity.normalized()

	# 至少完整走到预定目标时间以后，才允许按下落距离销毁。
	if (
		elapsed > maxf(0.20,minimum_flight_time)
		and confetti_velocity.y > 0.0
		and global_position.y >= spawn_position.y + maxf(fall_delete_distance,16.0)
	):
		Game.free_node(self)
		return

	# Area2D 的重叠检测是离散物理帧检测。彩带又细又多，
	# 单纯依赖 area_entered 时，恰好一帧跨过 Hurtbox 就会看起来“碰到了但没触发”。
	# 每帧先补查当前重叠，再用上一帧 -> 当前帧的线段做一次扫掠兜底。
	for overlap:Area2D in get_overlapping_areas():
		_try_trigger_area(overlap)
		if triggered:
			return
	_process_confetti_swept_hits(before_move,global_position)


func _on_area_entered(area:Area2D) -> void:
	_try_trigger_area(area)


func _try_trigger_area(area:Area2D) -> void:
	if not is_multiplayer_authority():
		return
	if not armed:
		return
	if area == null or not area is hurtbox:
		return
	if area.owner == null or not area.owner is ball:
		return

	var target:ball = area.owner as ball
	_try_trigger_target(
		target,
		{"shape":"circle","center":global_position,"radius":maxf(confetti_sweep_radius,1.0),"source":self}
	)


func _try_trigger_target(target:ball,damage_space:Variant = null) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.health <= 0:
		return
	if object_mode == ObjectMode.BANANA:
		if target.Type != ball.Ball_Type.Ball:
			return
		if triggered:
			return
		triggered = true
		# 当前函数可能来自 area_entered 物理回调，不能在 in/out signal 处理中
		# 直接修改 Area2D.monitoring；用 deferred 安全关闭。
		set_deferred("monitoring",false)
		var master:ball = _resolve_master()
		if master != null and master.has_method("_apply_banana_slip"):
			master.call("_apply_banana_slip",target)
		Game.free_node(self)
		return

	if not target.is_combat_targetable():
		return

	# 彩带是一次性投射物：只要第一次真正命中可伤害目标，就立刻进入销毁状态。
	# triggered 必须在造成伤害前置 true，避免 area_entered / overlap / sweep
	# 在同一物理帧里同时命中多个目标。
	if triggered:
		return

	var target_id:int = target.get_instance_id()
	if hit_ids.has(target_id):
		return

	var confetti_master:ball = _resolve_master()
	if confetti_master == null:
		return
	if not confetti_master.has_method("_can_damage_ball"):
		return
	if not bool(confetti_master.call("_can_damage_ball",target)):
		return

	if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,damage_amount)):
		triggered = true
		hit_ids[target_id] = true
		set_deferred("monitoring",false)
		Game.free_node(self)
		return

	triggered = true
	hit_ids[target_id] = true
	set_deferred("monitoring",false)

	if confetti_master.has_method("_clown_damage_target"):
		var resolved_space:Variant = damage_space
		if resolved_space == null:
			resolved_space = {"shape":"circle","center":global_position,"radius":maxf(confetti_sweep_radius,1.0),"source":self}
		confetti_master.call(
			"_clown_damage_target",
			target,
			damage_amount,
			(confetti_velocity.normalized() if confetti_velocity.length_squared() > 0.001 else direction.normalized()) * 42.0,
			false,
			true,
			resolved_space
		)

	# queue_free() 会在当前帧安全结束后删除；triggered 会阻止销毁前的重复命中。
	Game.free_node(self)


func _process_confetti_swept_hits(start:Vector2,finish:Vector2) -> void:
	if object_mode != ObjectMode.CONFETTI or triggered:
		return

	var segment:Vector2 = finish - start
	var segment_len_sq:float = segment.length_squared()

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if hit_ids.has(target.get_instance_id()):
			continue

		var nearest:Vector2 = start
		if segment_len_sq > 0.0001:
			var t:float = clampf(
				(target.global_position - start).dot(segment) / segment_len_sq,
				0.0,
				1.0
			)
			nearest = start + segment * t

		if target.global_position.distance_to(nearest) <= maxf(confetti_sweep_radius,1.0):
			_try_trigger_target(
				target,
				{"shape":"capsule","from":start,"to":finish,"half_width":maxf(confetti_sweep_radius,1.0),"source":self}
			)


func _resolve_master() -> ball:
	if is_instance_valid(Master):
		return Master

	var world:Node = get_tree().current_scene
	if world != null and Master_name != "":
		var found:Node = world.get_node_or_null(Master_name)
		if found is ball:
			Master = found as ball
			return Master

	return null
