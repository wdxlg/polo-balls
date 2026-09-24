extends ball

const RABBIT_SCENE := preload("res://scenes/characters/动物/兔子.tscn")
const RABBIT_BREED_EFFECT := preload("res://scenes/effects/兔子繁殖特效.tscn")

@export_category("外观")
@export var adult_texture:Texture2D
@export var baby_texture:Texture2D

@export_category("繁殖")
@export_range(0.0,10.0,0.1) var breed_cooldown:float = 1.3
@export_range(1,100,1) var max_rabbits_per_team:int = 24
@export_range(0.1,10.0,0.1) var baby_growth_time:float = 5.2
@export_range(1,5000,1) var baby_max_health:int = 36
@export_range(0.1,1.0,0.05) var baby_scale_ratio:float = 0.58
@export_range(0.0,200.0,1.0) var baby_spawn_offset:float = 42.0
@export_range(0.0,100.0,1.0) var baby_spawn_map_margin:float = 24.0

@export_category("初始兔群")
@export var spawn_initial_pair:bool = true
@export_range(1,2,1) var initial_rabbit_count:int = 2
@export_range(20.0,120.0,1.0) var initial_pair_spacing:float = 48.0

var is_baby:bool = false
var _adult_max_health:int = 0
var _adult_scale:Vector2 = Vector2.ONE
var _breed_cooldown_left:float = 0.0
var _growth_started:bool = false
var _initial_pair_spawned:bool = false


func _ensure_initial_rabbit_team() -> void:
	# 项目规则里空 Team 代表自由混战的“独立阵营”。
	# 一次上场的两只兔子必须互为同队，否则 _can_breed_with() 会拒绝繁殖。
	var current_team:String = str(Team).strip_edges()
	if not current_team.is_empty() and current_team != "Ball":
		return
	if not is_multiplayer_authority():
		return

	var setup_part:String = ""
	if has_meta("battle_setup_id"):
		setup_part = str(get_meta("battle_setup_id"))
	if setup_part.is_empty():
		setup_part = str(get_instance_id())
	Team = "__rabbit_family_" + setup_part


# V377：死亡回归重新实例化兔子时，PackedScene 的默认值会先经历 _ready()，
# 然后时间轴才写回历史脚本变量。若不提前准备，默认 spawn_initial_pair=true
# 会在 _ready() 里排队再生一只伙伴，导致目标快照 3 只恢复成 4 只。
# 由死亡回归时间轴在 add_child() 前调用；普通出生流程不会进入这里。
func prepare_death_return_recreate(state:Dictionary) -> void:
	set_meta("v323_rewind_recreating",true)
	Team = String(state.get("team",Team))
	direction = state.get("direction",direction)

	var script_values:Dictionary = state.get("script_values",{}) as Dictionary
	# is_baby 必须在入树前恢复，否则幼兔会先按成年兔执行 _ready()。
	if script_values.has("is_baby"):
		is_baby = bool(script_values["is_baby"])

	# 回归重建绝不能执行“玩家正常放下一只兔子时自动补第二只”的一次性出生逻辑。
	# 完整历史值会在 _ready() 后由时间轴 _apply_node_state() 正式写回。
	spawn_initial_pair = false
	_initial_pair_spawned = true
	# 若历史里是幼兔，重新建立成长计时；完整快照没有保存 SceneTreeTimer 剩余时间。
	if is_baby:
		_growth_started = false


# 入树时先决定幼兔生命上限，早于父类 @onready health = Max_health。
# 出生不是从成年生命扣到幼兔生命，不能触发伤害镜头、暴击粒子或受击钩子。
func _enter_tree() -> void:
	if is_baby and _adult_max_health <= 0:
		_adult_max_health = Max_health
		Max_health = mini(maxi(baby_max_health,1),maxi(_adult_max_health,1))


func _ready() -> void:
	# 在父类初始化前确定家庭队伍，确保随后生成的第二只兔子和繁殖幼兔继承同一阵营。
	if not is_baby:
		_ensure_initial_rabbit_team()
	if not is_baby:
		_adult_max_health = Max_health
	_adult_scale = scale

	# 在父类读取 image 节点前先放入正确纹理，确保碰撞反馈/残影系统拿到 Sprite2D。
	var sprite:Sprite2D = $Graphics/Image
	if is_baby and baby_texture != null:
		sprite.texture = baby_texture
	elif adult_texture != null:
		sprite.texture = adult_texture

	if is_baby:
		default_properties["Max_health"] = Max_health
		scale = _adult_scale * baby_scale_ratio

	super._ready()

	if is_baby and not _growth_started:
		_growth_started = true
		call_deferred("_grow_after_delay")

	# 玩家正常放下一次兔子时，权威端自动补出第二只成年兔。
	# 自动生成的伙伴会提前关闭 spawn_initial_pair，因此不会递归变成 4、8、16 只。
	if (
		is_multiplayer_authority()
		and not is_baby
		and spawn_initial_pair
		and initial_rabbit_count >= 2
		and not _initial_pair_spawned
		and not has_meta("v323_rewind_recreating")
	):
		_initial_pair_spawned = true
		call_deferred("_spawn_initial_partner")


func tick_physics(state:State,delta:float) -> void:
	_breed_cooldown_left = maxf(_breed_cooldown_left - delta,0.0)
	super.tick_physics(state,delta)


func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	var other = collision.get_collider()
	if is_multiplayer_authority() and _can_breed_with(other):
		# 同一次实体碰撞只允许一边生成一次。
		_spawn_baby_with(other as ball)

	super.when_collide(speed,collision)


func _can_breed_with(other) -> bool:
	if is_baby or _breed_cooldown_left > 0.0:
		return false
	if other == null or not is_instance_valid(other) or not (other is ball):
		return false
	if not other.has_method("is_adult_rabbit"):
		return false
	if not bool(other.call("is_adult_rabbit")):
		return false
	if float(other.get("_breed_cooldown_left")) > 0.0:
		return false
	if Team == "" or other.Team == "" or Team != other.Team:
		return false
	if other.health <= 0:
		return false
	return _count_team_rabbits() < maxi(max_rabbits_per_team,2)


func is_adult_rabbit() -> bool:
	return not is_baby and health > 0


func _count_team_rabbits() -> int:
	var count:int = 0
	for node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		if node.Team != Team:
			continue
		if node.has_method("is_adult_rabbit"):
			count += 1
	return count


func _get_map_rect() -> Rect2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	if not world.map_group.has(str(world.now_choose_map)):
		return Rect2()
	var map_node = world.map_group[str(world.now_choose_map)]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.return_map_world_rect(map_node)


func _clamp_spawn_to_map(point:Vector2) -> Vector2:
	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return point

	var margin:float = maxf(baby_spawn_map_margin,4.0)
	var min_x:float = rect.position.x + margin
	var max_x:float = rect.end.x - margin
	var min_y:float = rect.position.y + margin
	var max_y:float = rect.end.y - margin
	if min_x > max_x:
		min_x = (rect.position.x + rect.end.x) * 0.5
		max_x = min_x
	if min_y > max_y:
		min_y = (rect.position.y + rect.end.y) * 0.5
		max_y = min_y
	return Vector2(clampf(point.x,min_x,max_x),clampf(point.y,min_y,max_y))


func _choose_safe_baby_position(partner:ball) -> Vector2:
	var midpoint:Vector2 = (global_position + partner.global_position) * 0.5
	var tangent:Vector2 = partner.global_position - global_position
	if tangent.length_squared() <= 0.000001:
		tangent = Vector2.RIGHT
	tangent = tangent.normalized()
	var normal:Vector2 = tangent.rotated(PI * 0.5)
	var offset:float = maxf(baby_spawn_offset,8.0)

	# 先尝试碰撞连线两侧，再尝试四个斜方向。每个候选都会被压回地图内部。
	var candidates:Array[Vector2] = [
		midpoint + normal * offset,
		midpoint - normal * offset,
		midpoint + (normal + tangent).normalized() * offset,
		midpoint + (normal - tangent).normalized() * offset,
		midpoint + (-normal + tangent).normalized() * offset,
		midpoint + (-normal - tangent).normalized() * offset,
		midpoint
	]

	var best:Vector2 = _clamp_spawn_to_map(midpoint)
	var best_clearance:float = -INF
	for raw_point in candidates:
		var point:Vector2 = _clamp_spawn_to_map(raw_point)
		# 优先选择同时离两只成年兔更远的位置，降低新生兔被 safe_margin 顶出墙外的概率。
		var clearance:float = minf(
			point.distance_to(global_position),
			point.distance_to(partner.global_position)
		)
		if clearance > best_clearance:
			best_clearance = clearance
			best = point
	return best


func _choose_initial_partner_position() -> Vector2:
	var spacing:float = maxf(initial_pair_spacing,24.0)
	var base_dir:Vector2 = direction
	if base_dir.length_squared() <= 0.000001:
		base_dir = Vector2.from_angle(randf_range(0.0,TAU))
	base_dir = base_dir.normalized()

	# 优先放在原兔子的侧后方，减少两只兔子生成后立刻正面互撞并马上繁殖第三只的概率。
	var side:Vector2 = base_dir.rotated(PI * 0.5)
	if randf() < 0.5:
		side = -side
	var candidates:Array[Vector2] = [
		global_position + side * spacing,
		global_position - side * spacing,
		global_position - base_dir * spacing,
		global_position + base_dir * spacing
	]
	for candidate:Vector2 in candidates:
		var clamped:Vector2 = _clamp_spawn_to_map(candidate)
		if clamped.distance_to(global_position) >= spacing * 0.55:
			return clamped
	return _clamp_spawn_to_map(global_position + side * spacing)


func _spawn_initial_partner() -> void:
	if not is_instance_valid(self) or health <= 0 or is_baby:
		return
	if not is_multiplayer_authority():
		return

	# 原兔和伙伴都先进入一次繁殖冷却，防止刚出生贴得较近时立刻碰撞生出第三只。
	_breed_cooldown_left = maxf(breed_cooldown,0.0)

	var partner:ball = RABBIT_SCENE.instantiate()
	partner.set("is_baby",false)
	partner.set("spawn_initial_pair",false)
	partner.set("_initial_pair_spawned",true)
	partner.set("_breed_cooldown_left",maxf(breed_cooldown,0.0))
	partner.Team = Team
	partner.Target_Enemy = Target_Enemy
	partner.direction = -direction if direction.length_squared() > 0.000001 else Vector2.from_angle(randf_range(0.0,TAU))
	partner.name = Game.return_random_name(partner)

	var world := get_tree().current_scene
	if world == null:
		partner.free()
		return
	# 先把关键身份/递归开关写好再入树；加入后再写 global_position，保持与现有幼兔生成逻辑一致。
	world.add_child(partner,true)
	partner.global_position = _choose_initial_partner_position()


func _spawn_baby_with(partner:ball) -> void:
	if _count_team_rabbits() >= maxi(max_rabbits_per_team,2):
		return

	_breed_cooldown_left = breed_cooldown
	partner.set("_breed_cooldown_left",breed_cooldown)

	# 繁殖反馈固定从两只成年兔的正中间开始。
	var breed_position:Vector2 = (global_position + partner.global_position) * 0.5

	var baby:ball = RABBIT_SCENE.instantiate()
	baby.set("is_baby",true)
	baby.Team = Team
	baby.Target_Enemy = Target_Enemy
	baby.direction = Vector2.from_angle(randf_range(0.0,TAU))
	baby.name = Game.return_random_name(baby)

	# 先入树再写 global_position，避免父节点 Transform 参与换算时把出生点带偏。
	get_tree().current_scene.add_child(baby,true)
	baby.global_position = _choose_safe_baby_position(partner)

	# 幼兔真正生成成功后才播放，避免“碰撞但未繁殖”也出现音效/爱心。
	_play_breed_feedback.rpc(breed_position)


@rpc("authority","call_local","unreliable")
func _play_breed_feedback(world_position:Vector2) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	var effect:Node2D = RABBIT_BREED_EFFECT.instantiate()
	world.add_child(effect,true)
	effect.global_position = world_position


func _grow_after_delay() -> void:
	await get_tree().create_timer(maxf(baby_growth_time,0.05)).timeout
	if not is_instance_valid(self) or health <= 0:
		return

	var health_ratio:float = 1.0
	if Max_health > 0:
		health_ratio = clampf(float(health) / float(Max_health),0.0,1.0)

	is_baby = false
	if image is Sprite2D and adult_texture != null:
		(image as Sprite2D).texture = adult_texture
	Max_health = maxi(_adult_max_health,1)
	default_properties["Max_health"] = Max_health
	scale = _adult_scale
	health_bar.suppress_floating_text = true
	health = maxi(int(round(float(Max_health) * health_ratio)),1)
	health_bar.suppress_floating_text = false


func Die() -> void:
	super()
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(self):
		Game.free_node(self)
