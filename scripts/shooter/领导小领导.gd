extends Node2D

const LEADER_ANGRY_TEXTURE:Texture2D = preload("res://Images/characters/人物/领导/领导生气(2).png")
const LEADER_SMILE_TEXTURE:Texture2D = preload("res://Images/characters/人物/领导/领导笑(2).png")

var owner_leader:Node = null
var authoritative_logic:bool = false
var projectile_team:String = ""
var travel_direction:Vector2 = Vector2.RIGHT
var projectile_speed:float = 300.0
var max_lifetime:float = 5.0
var lecture_stun:float = 1.45
var hit_radius:float = 11.0
var elapsed:float = 0.0

var lecturing:bool = false
var lecture_elapsed:float = 0.0
var lecture_duration:float = 1.45
var lecture_target:ball = null
var lecture_offset:Vector2 = Vector2(42.0,0.0)

@onready var visual:Sprite2D = $Visual


func configure(owner_node:Node,config:Dictionary,is_authority:bool) -> void:
	owner_leader = owner_node
	authoritative_logic = is_authority
	global_position = config.get("origin",global_position)
	travel_direction = config.get("direction",Vector2.RIGHT)
	if travel_direction.length_squared() <= 0.000001:
		travel_direction = Vector2.RIGHT
	travel_direction = travel_direction.normalized()
	projectile_speed = maxf(float(config.get("speed",300.0)),1.0)
	max_lifetime = maxf(float(config.get("lifetime",5.0)),0.1)
	lecture_stun = maxf(float(config.get("stun",1.45)),0.05)
	projectile_team = str(config.get("team",""))
	z_as_relative = false
	z_index = 81
	rotation = 0.0
	add_to_group("BattleTransient")
	_set_visual_state(false)


func _set_visual_state(angry:bool) -> void:
	if visual == null:
		return
	var texture:Texture2D = LEADER_ANGRY_TEXTURE if angry else LEADER_SMILE_TEXTURE
	visual.texture = texture
	visual.visible = true
	var max_dimension:float = maxf(float(maxi(texture.get_width(),texture.get_height())),1.0)
	var target_size:float = 44.0 if angry else 38.0
	visual.scale = Vector2.ONE * (target_size / max_dimension)
	if angry:
		# V320：说教后的愤怒领导永远只有“朝左 / 朝右”两种正立姿态。
		# 根和 Visual 都固定 rotation=0，禁止继承飞行阶段任何斜角；原图朝右，位于目标右侧时水平翻转朝左。
		rotation = 0.0
		visual.rotation = 0.0
		visual.flip_v = false
		visual.flip_h = lecture_offset.x > 0.0
	else:
		_apply_flight_visual_orientation()


func _apply_flight_visual_orientation() -> void:
	if visual == null:
		return
	# V320：飞行中的小领导允许沿真实飞行方向旋转，但绝不能因为角度越过左半平面而上下倒立。
	# Sprite2D.flip_v 是纹理垂直翻转；当 direction.x<0 时配合原旋转角使用，等效于把倒立的人物重新翻正。
	var angle:float = wrapf(travel_direction.angle(),-PI,PI)
	visual.rotation = angle
	visual.flip_h = false
	visual.flip_v = travel_direction.x < 0.0


func _physics_process(delta:float) -> void:
	if lecturing:
		_tick_lecture(delta)
		return

	elapsed += delta
	var from_pos:Vector2 = global_position
	var to_pos:Vector2 = from_pos + travel_direction * projectile_speed * delta
	# 小领导明确无视障碍物：不做 Layer1 terrain raycast。
	global_position = to_pos
	_apply_flight_visual_orientation()
	if authoritative_logic:
		var target:ball = _first_enemy_hit(from_pos,to_pos)
		if target != null:
			target.apply_stun(lecture_stun)
			_sync_begin_lecture(target)
			return
	if _outside_map() or elapsed >= max_lifetime:
		if authoritative_logic:
			_remove_self_synced()
		else:
			queue_free()


func _sync_begin_lecture(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		_remove_self_synced()
		return
	if owner_leader != null and is_instance_valid(owner_leader) and owner_leader.has_method("_call_mini_leader_lecture"):
		owner_leader.call("_call_mini_leader_lecture",str(name),target.get_path(),lecture_stun)
	else:
		begin_lecture(target,lecture_stun)


func begin_lecture(target:ball,duration:float) -> void:
	if target == null or not is_instance_valid(target):
		return
	lecturing = true
	lecture_target = target
	lecture_elapsed = 0.0
	lecture_duration = maxf(duration,0.05)
	# 命中后严格按飞来的水平侧停在敌人左/右两边之一；Y 固定为0。
	var side_sign:float = -1.0 if travel_direction.x >= 0.0 else 1.0
	lecture_offset = Vector2(42.0 * side_sign,0.0)
	rotation = 0.0
	_set_visual_state(true)
	global_position = target.global_position + lecture_offset


func _tick_lecture(delta:float) -> void:
	lecture_elapsed += delta
	if lecture_target != null and is_instance_valid(lecture_target):
		global_position = lecture_target.global_position + lecture_offset
		rotation = 0.0
		if visual != null:
			# V320：说教阶段每帧强制恢复正角，只允许水平左右镜像，不允许任意旋转或垂直翻转。
			visual.rotation = 0.0
			visual.flip_v = false
			visual.flip_h = lecture_offset.x > 0.0
	if lecture_elapsed >= lecture_duration or lecture_target == null or not is_instance_valid(lecture_target):
		if authoritative_logic:
			_remove_self_synced()
		elif not multiplayer.has_multiplayer_peer():
			queue_free()


func _remove_self_synced() -> void:
	if authoritative_logic and owner_leader != null and is_instance_valid(owner_leader) and owner_leader.has_method("_call_remove_runtime_node"):
		owner_leader.call("_call_remove_runtime_node",str(name))
	else:
		queue_free()


func _first_enemy_hit(from_pos:Vector2,to_pos:Vector2) -> ball:
	var best:ball = null
	var best_t:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball):
			continue
		var target:ball = raw as ball
		if target == owner_leader or not target.is_combat_targetable():
			continue
		if (
			not bool(Game.Game_Settings.get("Have_Team_Damage",false))
			and projectile_team != ""
			and target.Team != ""
			and target.Team == projectile_team
		):
			continue
		var t:float = _segment_parameter(target.global_position,from_pos,to_pos)
		var closest:Vector2 = from_pos.lerp(to_pos,t)
		if target.global_position.distance_to(closest) <= hit_radius + 12.0 and t < best_t:
			best_t = t
			best = target
	return best


func _segment_parameter(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return 0.0
	return clampf((point - a).dot(ab) / len_sq,0.0,1.0)


func _outside_map() -> bool:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return false
	var map_group:Variant = world.get("map_group")
	var map_index:Variant = world.get("now_choose_map")
	if not (map_group is Array) or int(map_index) < 0 or int(map_index) >= (map_group as Array).size():
		return false
	var map_node:Variant = (map_group as Array)[int(map_index)]
	if not (map_node is TileMapLayer):
		return false
	var rect:Rect2 = world.call("return_map_world_rect",map_node)
	return not rect.grow(28.0).has_point(global_position)
